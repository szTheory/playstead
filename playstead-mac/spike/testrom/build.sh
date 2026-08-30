#!/usr/bin/env bash
# Builds savetest.gba — the spike's own minimal, SRAM-writing homebrew test
# title (MIT, written for this spike, no third-party ROM sourcing needed).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

arm-none-eabi-gcc -mthumb-interwork -mcpu=arm7tdmi -mtune=arm7tdmi \
  -fomit-frame-pointer -ffast-math -O2 \
  -c crt0.s -o crt0.o

arm-none-eabi-gcc -mthumb-interwork -mcpu=arm7tdmi -mtune=arm7tdmi \
  -fomit-frame-pointer -ffast-math -O2 -std=c11 \
  -c main.c -o main.o

arm-none-eabi-gcc -mthumb-interwork -mcpu=arm7tdmi -mtune=arm7tdmi \
  -nostdlib -T linker.ld crt0.o main.o -o savetest.elf

arm-none-eabi-objcopy -O binary savetest.elf savetest.gba

python3 fix-header.py savetest.gba

echo "==> Built savetest.gba ($(wc -c < savetest.gba) bytes)"
shasum -a 256 savetest.gba
