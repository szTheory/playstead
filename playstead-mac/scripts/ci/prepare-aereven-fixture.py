#!/usr/bin/env python3
"""Materialize an isolated Aereven registry from the existing pinned fixture."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import sys
from pathlib import Path

EXPECTED_ROM_SHA256 = "de968dca9f86f1648bb2bb992d6ce4aa4007d3bf7a064b4bbfd82a96e29409ab"
EXPECTED_ROM_SIZE = 5_564_940
EXPECTED_SAVE_SHA256 = "8efc60d327e3c485e0d5bdcd93503059d1ea9f92dcd8f14813b39f689e5aa9cf"
EXPECTED_SAVE_SIZE = 32_768


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verified_file(row: dict[str, object], digest: str, size: int) -> Path | None:
    raw = row.get("path")
    if not isinstance(raw, str) or not raw:
        return None
    path = Path(raw)
    if path.is_symlink() or not path.is_file() or path.stat().st_size != size:
        return None
    if row.get("sha256") != digest or row.get("size_bytes") != size or sha256(path) != digest:
        return None
    return path


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: prepare-aereven-fixture.py REGISTRY OUTPUT_DIRECTORY")
    registry, output_root = map(Path, sys.argv[1:])
    if registry.is_symlink() or not registry.is_file() or stat.S_IMODE(registry.stat().st_mode) != 0o600:
        raise SystemExit("Aereven registry missing or unsafe")
    data = json.loads(registry.read_text(encoding="utf-8"))
    if (data.get("schema"), data.get("fixture_id"), data.get("system_id")) != (
        "playstead.local-test-fixture.v1", "aerevenadvance", "gba"
    ):
        raise SystemExit("Aereven registry identity rejected")
    game = data.get("game")
    save = data.get("persistent_save")
    if not isinstance(game, dict) or not isinstance(save, dict):
        raise SystemExit("Aereven source identities missing")

    source_game = verified_file(game, EXPECTED_ROM_SHA256, EXPECTED_ROM_SIZE)
    if source_game is None:
        downloads = Path.home() / "Downloads"
        candidates = []
        for path in downloads.rglob("*.gba"):
            if path.is_symlink() or not path.is_file() or path.stat().st_size != EXPECTED_ROM_SIZE:
                continue
            if sha256(path) == EXPECTED_ROM_SHA256:
                candidates.append(path)
        if not candidates:
            raise SystemExit("no Downloads ROM matches the existing Aereven registry digest")
        source_game = sorted(candidates, key=lambda path: str(path))[0]

    source_save = verified_file(save, EXPECTED_SAVE_SHA256, EXPECTED_SAVE_SIZE)
    if source_save is None:
        raise SystemExit("recorded Aereven persistent save is missing or changed")

    output_root.mkdir(mode=0o700, parents=True, exist_ok=False)
    working_rom = output_root / "AerevenAdvance.gba"
    working_save = output_root / "AerevenAdvance.sav"
    shutil.copyfile(source_game, working_rom)
    os.chmod(working_rom, 0o600)
    if working_rom.stat().st_size != EXPECTED_ROM_SIZE or sha256(working_rom) != EXPECTED_ROM_SHA256:
        raise SystemExit("isolated Aereven working copy failed digest verification")
    shutil.copyfile(source_save, working_save)
    os.chmod(working_save, 0o600)
    if working_save.stat().st_size != EXPECTED_SAVE_SIZE or sha256(working_save) != EXPECTED_SAVE_SHA256:
        raise SystemExit("isolated Aereven persistent-save copy failed digest verification")

    data["game"]["path"] = str(working_rom)
    data["persistent_save"]["path"] = str(working_save)
    temporary = output_root / "aerevenadvance.json.tmp"
    destination = output_root / "aerevenadvance.json"
    temporary.write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    temporary.replace(destination)
    print("aereven existing ROM/save identities verified; isolated working copies ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
