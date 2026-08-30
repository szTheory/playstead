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
    .data : { *(.data*) } > rom
    .bss (NOLOAD) : { *(.bss*) *(COMMON) } > iwram
}
