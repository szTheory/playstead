@ Minimal GBA cartridge header + startup stub for savetest.gba.
@ Written for this spike (Playstead project) — MIT license, not derived from
@ any third-party homebrew or Nintendo SDK source. The 156-byte "Nintendo
@ logo" region is left zeroed (compatibility logo checksum is not enforced by
@ mGBA's loader for homebrew/test content); only the header fields required
@ for mGBA to recognize a valid GBA ROM and pick a save type are populated.
    .arm
    .section .header, "ax"
    .global _start
_start:
    b       rom_start               @ 0xE0 boot branch, at ROM offset 0x00

    .fill   156, 1, 0                @ Nintendo logo region (0x04-0x9F) — left zeroed

    .ascii  "SAVETEST"               @ Game title, 12 bytes, offset 0xA0
    .fill   4, 1, 0
    .ascii  "PSTE"                   @ Game code, offset 0xAC
    .ascii  "01"                     @ Maker code, offset 0xB0
    .byte   0x96                     @ Fixed value, offset 0xB2
    .byte   0x00                     @ Main unit code, offset 0xB3
    .byte   0x00                     @ Device type, offset 0xB4
    .fill   7, 1, 0                  @ Reserved, offset 0xB5
    .byte   0x00                     @ Software version, offset 0xBC
    .byte   0x00                     @ Header checksum, offset 0xBD — patched post-link by fix-header.py
    .fill   2, 1, 0                  @ Reserved, offset 0xBE

    .section .text
rom_start:
    @ Set up stack pointers for IRQ and System modes, then call main().
    mov     r0, #0x12
    msr     cpsr_c, r0
    ldr     sp, =0x03007FA0

    mov     r0, #0x1F
    msr     cpsr_c, r0
    ldr     sp, =0x03007F00

    ldr     r0, =main
    bx      r0
hang:
    b       hang
