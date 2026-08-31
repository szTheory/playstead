OUTPUT_FORMAT("elf32-littlearm")
OUTPUT_ARCH(arm)
ENTRY(_start)

MEMORY {
    rom (rx) : ORIGIN = 0x08000000, LENGTH = 32M
    iwram (rwx) : ORIGIN = 0x03000000, LENGTH = 32K
}

SECTIONS {
    .header : { *(.header) } > rom
    .text : { *(.text*) } > rom
    .rodata : { *(.rodata*) } > rom

    /* P6-WR-005: `.data` (writable, initialized globals) must live in
       writable IWRAM at runtime (its VMA, via `> iwram`) while its
       initial byte values are baked into the read-only ROM image at
       build time (its LMA, via `AT> rom`) -- ROM cannot be written to
       on real hardware, so placing `.data`'s VMA in `rom` (the
       previous layout) would silently drop any runtime write to a
       writable global. crt0.s's startup stub copies LMA -> VMA before
       calling main(), the standard embedded-crt0 pattern. This ROM
       currently defines no writable globals (main.c's only global,
       save_type_marker, is const and lands in .rodata), so this was
       previously a dormant, silent-failure trap rather than an active
       bug -- kept correct here for the next writable global added. */
    .data : {
        __data_start = .;
        *(.data*)
        __data_end = .;
    } > iwram AT> rom
    __data_load_start = LOADADDR(.data);

    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss*) *(COMMON)
        __bss_end = .;
    } > iwram
}
