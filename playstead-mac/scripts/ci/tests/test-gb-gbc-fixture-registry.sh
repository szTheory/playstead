#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REPO_ROOT="$(cd "${MAC_ROOT}/.." && pwd)"
SERVER_TASK="${REPO_ROOT}/playstead-server/lib/mix/tasks/playstead.mac_ci_fixture.ex"
PREPARE_AEREVEN="${MAC_ROOT}/scripts/ci/prepare-aereven-fixture.py"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/playstead-gb-registry.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT

python3 "${REPO_ROOT}/.planning/spikes/001-bios-free-gameplay/build_fixture.py" --out "$temporary_root/generated"
python3 - "$temporary_root/generated/fixtures.json" "$temporary_root/generated" "$SERVER_TASK" "$PREPARE_AEREVEN" <<'PY'
import hashlib, importlib.util, json, pathlib, re, sys
registry, root, task = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]).resolve(), pathlib.Path(sys.argv[3]).read_text()
prepare_path = pathlib.Path(sys.argv[4])
rows = json.loads(registry.read_text())
expected = {
    "gb-mbc1-8k": ("gb", 3, 8192, False, "4d62166b5cd35185ac0977eb73fe5bc22b406141861832863f133d754f635aa4", 32768),
    "gbc-mbc5-32k": ("gbc", 27, 32768, False, "f9d914ba107bfd9676c730d315956a2d264c6e0e74e042afd729f493dcb40a3b", 32768),
    "gbc-mbc3-rtc": ("gbc", 16, 32768, True, "0edb186314a8fee38e00fec0c52e678ba24abf5b00198e3cfcb80c0d3e60cbc7", 32768),
}
assert len(rows) == len(expected)
for row in rows:
    name = row["name"]
    system, cart, save_bytes, rtc, digest, rom_bytes = expected[name]
    path = pathlib.Path(row["path"])
    assert path.parent.resolve() == root and not path.is_symlink()
    data = path.read_bytes()
    assert len(data) == rom_bytes and hashlib.sha256(data).hexdigest() == digest == row["sha256"]
    assert (row["system"], row["cartridge_type"], row["sram_bytes"], row["rtc"]) == (system, cart, save_bytes, rtc)
for digest in (item[4] for item in expected.values()):
    assert digest in task, f"production importer lost pinned fixture digest {digest}"
assert ".build/ci/gb-gbc-fixtures/fixtures.json" in task
assert ".local/gb-gbc-spike/fixtures/fixtures.json" in task
assert 'Path.join([profile_root, "aereven-fixture", "aerevenadvance.json"])' in task
assert 'Regex.match?(~r/^playstead-gb-save-e2e\\.[A-Za-z0-9]{6}$/,' in task
def accepts_run_root(root):
    return re.fullmatch(r"playstead-gb-save-e2e\.[A-Za-z0-9]{6}", pathlib.Path(root).name) is not None
assert accepts_run_root("/tmp/playstead-gb-save-e2e.aB12cD")
for invalid in ("/tmp/playstead-gb-save-e2e.short", "/tmp/playstead-gb-save-e2e.aB12cD-extra", "/tmp/owner-profile"):
    assert not accepts_run_root(invalid), invalid
spec = importlib.util.spec_from_file_location("prepare_aereven_fixture", prepare_path)
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)
wrong_save = root / "wrong-private-save.sav"
wrong_save.write_bytes(b"x" * prepare.EXPECTED_SAVE_SIZE)
assert prepare.verified_file({"path": str(wrong_save), "sha256": prepare.EXPECTED_SAVE_SHA256,
                             "size_bytes": prepare.EXPECTED_SAVE_SIZE},
                            prepare.EXPECTED_SAVE_SHA256, prepare.EXPECTED_SAVE_SIZE) is None
prepare_text = prepare_path.read_text()
assert 'working_save = output_root / "AerevenAdvance.sav"' in prepare_text
assert "os.chmod(working_save, 0o600)" in prepare_text
print("generated GB/GBC registry aliases, exact byte digests, and importer roots passed")
PY

python3 - "$REPO_ROOT" "$temporary_root" <<'PY'
import importlib.util, json, pathlib, shutil, stat, subprocess, sys
sys.dont_write_bytecode = True
repo, scratch = map(pathlib.Path, sys.argv[1:])
plan = json.loads((repo / "playstead-mac/TestPlans/LiveServer.xctestplan").read_text())
variables = {row["key"]: row["value"] for row in plan["defaultOptions"]["environmentVariableEntries"]}
assert variables["PLAYSTEAD_GB_GBC_SAVE_E2E_PROFILE_ROOT"] == "$(PLAYSTEAD_GB_GBC_SAVE_E2E_PROFILE_ROOT)"
workspace = scratch / "clean-checkout"
mac = workspace / "playstead-mac"
mac.mkdir(parents=True)
for directory, filename in (("001-bios-free-gameplay", "build_fixture.py"),
                            ("001-bios-free-gameplay", "verify_pixels.py"),
                            ("002-persistent-battery-saves", "oracle_command.py")):
    relative = pathlib.Path(".planning/spikes") / directory / filename
    destination = workspace / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(repo / relative, destination)
# Loading the real pixel verifier also loads its sibling font/fixture module.
# A missing transitive input must fail here before the costly native journey.
verifier_path = workspace / ".planning/spikes/001-bios-free-gameplay/verify_pixels.py"
spec = importlib.util.spec_from_file_location("clean_pixel_verifier", verifier_path)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)
assert callable(verifier.verify)
try:
    verifier.verify(scratch / "missing-screen.png", "gb", 0)
except FileNotFoundError:
    pass
else:
    raise AssertionError("pixel verifier accepted a missing screenshot")
lines = (repo / ".github/workflows/ci.yml").read_text().splitlines()
start = lines.index("      - name: Generate pinned self-authored GB/GBC fixtures")
run = next(i for i in range(start + 1, len(lines)) if lines[i].startswith("        run:"))
assert lines[run].strip() == "run: |", "fixture setup must include its output-directory preparation"
commands = []
for line in lines[run + 1:]:
    if line.strip() and not line.startswith("          "):
        break
    commands.append(line[10:])
result = subprocess.run(["/bin/bash", "-e", "-c", "\n".join(commands)], cwd=mac,
                        text=True, capture_output=True)
assert result.returncode == 0, result.stderr[-1000:]
rows = json.loads((mac / ".build/ci/gb-gbc-fixtures/fixtures.json").read_text())
assert len(rows) == 3
for row in rows:
    fixture = row["name"]
    output = mac / ".local/gb-gbc-spike" / fixture
    assert output.is_dir() and (output / "screenshots").is_dir(), fixture
    assert stat.S_IMODE(output.stat().st_mode) == 0o700
    assert stat.S_IMODE((output / "screenshots").stat().st_mode) == 0o700
    assert stat.S_IMODE(pathlib.Path(row["path"]).stat().st_mode) == 0o600
    command = subprocess.check_output(
        [sys.executable, str(workspace / ".planning/spikes/002-persistent-battery-saves/oracle_command.py"),
         fixture, "ci-smoke", "--observe-only"], text=True)
    assert str(output / "ci-smoke-oracle.json") in command
    assert str(output / "screenshots/ci-smoke-before.png") in command
    # These are the real generator's destinations; a clean runner must
    # permit creation there before an emulator can emit its observations.
    with (output / "ci-smoke-oracle.json").open("x") as handle:
        handle.write("{}\n")
    with (output / "screenshots/ci-smoke-before.png").open("xb") as handle:
        handle.write(b"output-path-smoke")
print("clean workflow setup prepared all three private oracle output paths")
PY
