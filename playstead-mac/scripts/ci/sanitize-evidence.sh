#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'evidence sanitizer: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 4 ] || die "usage: sanitize-evidence.sh --input ROOT --output DIRECTORY"
[ "$1" = "--input" ] || die "first argument must be --input"
INPUT_ROOT="$2"
[ "$3" = "--output" ] || die "third argument must be --output"
OUTPUT_ROOT="$4"

[ -d "$INPUT_ROOT/evidence" ] || die "input evidence directory is missing"
[ -n "$OUTPUT_ROOT" ] && [ "$OUTPUT_ROOT" != "/" ] || die "unsafe output directory"
[ "$INPUT_ROOT" != "$OUTPUT_ROOT" ] || die "input and output directories must differ"

rm -rf "$OUTPUT_ROOT"
mkdir -p "$OUTPUT_ROOT"

python3 - "$INPUT_ROOT/evidence" "$OUTPUT_ROOT" <<'PY'
import json, pathlib, re, shutil, sys

source = pathlib.Path(sys.argv[1]).resolve()
output = pathlib.Path(sys.argv[2]).resolve()
max_files = 40
max_total = 12 * 1024 * 1024
max_text = 256 * 1024
max_image = 2 * 1024 * 1024

allowed = []
for name in ("environment-fingerprint.json", "layers.json"):
    candidate = source / name
    if candidate.is_file():
        allowed.append(candidate)
allowed.extend(sorted(source.glob("*-tests.json")))
for name in ("reference.png", "actual.png", "diff.png"):
    candidate = source / "snapshot-triplet" / name
    if candidate.is_file():
        allowed.append(candidate)
allowed.extend(sorted((source / "screenshots").glob("synthetic-*.png")) if (source / "screenshots").is_dir() else [])
if (source / "accessibility").is_dir():
    allowed.extend(sorted((source / "accessibility").glob("*.tree.txt")))
    allowed.extend(sorted((source / "accessibility").glob("*.focus.txt")))
if (source / "logs").is_dir():
    for name in ("app.log", "server.log"):
        candidate = source / "logs" / name
        if candidate.is_file():
            allowed.append(candidate)

allowed = list(dict.fromkeys(allowed))
if not allowed:
    raise SystemExit("no allowlisted evidence files were found")
if len(allowed) > max_files:
    raise SystemExit(f"evidence file count exceeds {max_files}")

sensitive_keys = {
    "authorization", "credential", "credentials", "token", "database_url",
    "raw_log", "keychain_path", "handoff", "environment", "env",
}
sensitive_text = re.compile(
    r"(?i)(authorization\s*[:=]|bearer\s+[A-Za-z0-9._~+/=-]+|"
    r"database_url\s*=|secret_key_base\s*=|\.keychain(?:-db)?\b|"
    r"(?:^|[/\\])\.env(?:\b|[/\\])|credential[-_ ]?handoff|"
    r"(?:^|[/\\])(?:objects|partials)(?:[/\\]|$)|"
    r"\b[0-9a-f]{64}\b|\.(?:rom|nes|sfc|smc|gba|gbc|iso|chd|cue|bios)\b)"
)
path_text = re.compile(r"(?:file://)?/(?:Users|private|var/folders|tmp)/[^\s\"']+")

def scan_json(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in sensitive_keys:
                raise SystemExit(f"secret-bearing JSON key is forbidden: {key}")
            scan_json(child)
    elif isinstance(value, list):
        for child in value:
            scan_json(child)
    elif isinstance(value, str):
        if sensitive_text.search(value) or path_text.search(value):
            raise SystemExit("secret, content identifier, or local path found in structured evidence")

def sanitize_log(raw):
    lines = []
    for line in raw.splitlines():
        if sensitive_text.search(line):
            lines.append("[REDACTED SECRET-BEARING LINE]")
        else:
            lines.append(path_text.sub("[PATH]", line))
    return "\n".join(lines) + ("\n" if raw.endswith("\n") else "")

manifest = []
total = 0
for item in allowed:
    relative = item.relative_to(source)
    if any(part in {"DerivedData", ".snapshot-testing"} or part.endswith(".xcresult") for part in relative.parts):
        raise SystemExit(f"raw build material is forbidden: {relative}")
    suffix = item.suffix.lower()
    limit = max_image if suffix == ".png" else max_text
    size = item.stat().st_size
    if size <= 0 or size > limit:
        raise SystemExit(f"evidence file size is invalid: {relative} ({size} bytes)")
    total += size
    if total > max_total:
        raise SystemExit(f"evidence total exceeds {max_total} bytes")

    destination = output / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    if suffix == ".json":
        try:
            data = json.loads(item.read_text(encoding="utf-8"))
        except Exception as exc:
            raise SystemExit(f"invalid JSON evidence {relative}: {exc}")
        scan_json(data)
        destination.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    elif suffix == ".txt" or suffix == ".log":
        destination.write_text(sanitize_log(item.read_text(encoding="utf-8")), encoding="utf-8")
    elif suffix == ".png":
        shutil.copyfile(item, destination)
    else:
        raise SystemExit(f"evidence extension is not allowlisted: {relative}")
    manifest.append({"path": str(relative), "size_bytes": destination.stat().st_size})

for item in output.rglob("*"):
    if not item.is_file() or item.name == "manifest.json":
        continue
    if item.suffix.lower() != ".png":
        raw = item.read_text(encoding="utf-8")
        if sensitive_text.search(raw) or path_text.search(raw):
            raise SystemExit(f"post-sanitization scan failed: {item.relative_to(output)}")

(output / "manifest.json").write_text(json.dumps({
    "schema_version": 1,
    "file_count": len(manifest),
    "total_size_bytes": sum(entry["size_bytes"] for entry in manifest),
    "files": manifest,
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"staged {len(manifest)} sanitized evidence file(s), {total} input byte(s)")
PY
