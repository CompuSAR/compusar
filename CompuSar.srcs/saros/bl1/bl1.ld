# Linker script for Boot Loader stage 1

MEM_BASE = 0x80000000;
CACHE_SIZE = 16K;

MEMORY { preload : ORIGIN = MEM_BASE, LENGTH = CACHE_SIZE }
MEMORY { discard : ORIGIN = 0x1000000, LENGTH = 0x1000000 }
MEMORY { error : ORIGIN = 0xf0000000, LENGTH = 0 }
ENTRY(_start)
SECTIONS
{
    .text : AT(MEM_BASE) {
        start.o (.text*)
        * (.text*)
    } >preload
    .rodata : ALIGN(16) {
         *(.rodata*)
    } >preload

    PROVIDE(__global_pointer$ = . + 2K);
    .srodata : ALIGN(16) {
        *(.srodata*)
    } >preload

    .sdata : ALIGN(16) {
         *(.sdata*)
    } >preload

    .sbss : ALIGN(16) {
        BSS_START = .;
        * (.sbss*)
    } >preload

    .bss : ALIGN(16) {
        * (.bss*)
        . = ALIGN(16);
        BSS_END = .;

        . = ALIGN(16);
        OS_LOAD_BUFFER = .;
        . = . + 4096;
        OS_LOAD_BUFFER_END = .;
    } >preload

    .data : ALIGN(16) {
         *(.data*)
    } >preload

    .got : ALIGN(4) {
        *(.got)
    } > preload

    .got.plt : ALIGN(4) {
        *(.got.plt)
    } > preload

    PROVIDE(__stack_end = MEM_BASE + CACHE_SIZE);

    /DISCARD/ : { *(.eh_frame) *(.note.GNU-stack) }

    .debug_info : { *(.debug_info) }
    .debug_abbrev : { *(.debug_abbrev) }
    .debug_loc : { *(.debug_loc) }
    .debug_aranges : { *(.debug_aranges) }
    .debug_line : { *(.debug_line) }
    .debug_str : { *(.debug_str) }
    .debug_ranges : { *(.debug_ranges) }
    .debug_line_str : { *(.debug_line_str) }
    .debug_loclists : { *(.debug_loclists) }
    .debug_rnglists : { *(.debug_rnglists) }
    .debug_frame : { *(.debug_frame) }
    .riscv.attributes : { *(.riscv.attributes) } >discard
    .comment : { *(.comment) } >discard
    .rela.text : { *(.rela.text) } > error

    PROVIDE(DDR_MEMORY = MEM_BASE + 64K);
}
