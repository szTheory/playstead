#!/usr/bin/env python3
"""Patches the GBA cartridge header checksum (byte 0xBD) per the standard
GBA header checksum algorithm: -(sum(bytes[0xA0:0xBD]) + 0x19) & 0xFF.
"""
import sys

if len(sys.argv) != 2:
    print("usage: fix-header.py <rom-path>", file=sys.stderr)
    sys.exit(64)
path = sys.argv[1]
with open(path, "r+b") as f:
    data = bytearray(f.read())
    if len(data) < 0xC0:
        data.extend(b"\x00" * (0xC0 - len(data)))
    checksum = 0
    for b in data[0xA0:0xBD]:
        checksum += b
    checksum = (-(checksum + 0x19)) & 0xFF
    data[0xBD] = checksum
    f.seek(0)
    f.write(data)
    f.truncate()
print(f"header checksum patched: 0x{checksum:02x}")
