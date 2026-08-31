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

    @ P6-WR-005: copy .data's initial values from their ROM load
    @ address (baked in at link time via linker.ld's `AT> rom`) to
    @ their IWRAM run address, and zero .bss, before main() can read
    @ or write any global. Without this, a writable global's initial
    @ value would only ever exist at its ROM address -- unreachable at
    @ runtime since .data's VMA is IWRAM -- and any write to it would
    @ hit uninitialized/stale IWRAM contents instead.
    ldr     r0, =__data_load_start
    ldr     r1, =__data_start
    ldr     r2, =__data_end
copy_data_loop:
    cmp     r1, r2
    bge     copy_data_done
    ldrb    r3, [r0], #1
    strb    r3, [r1], #1
    b       copy_data_loop
copy_data_done:

    ldr     r0, =__bss_start
    ldr     r1, =__bss_end
    mov     r2, #0
zero_bss_loop:
    cmp     r0, r1
    bge     zero_bss_done
    strb    r2, [r0], #1
    b       zero_bss_loop
zero_bss_done:

    ldr     r0, =main
    bx      r0
hang:
    b       hang
