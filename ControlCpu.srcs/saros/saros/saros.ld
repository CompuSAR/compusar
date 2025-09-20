# Linker script for Saros

MEM_BASE = 0x80000000;
APPLE2_ROMS = MEM_BASE + 16M;

MEMORY { preload(rwx) : ORIGIN = MEM_BASE, LENGTH = 64K }
MEMORY { discard : ORIGIN = 0x1000000, LENGTH = 0x1000000 }
MEMORY { error : ORIGIN = 0xf0000000, LENGTH = 0 }
MEMORY { exe(rx) : ORIGIN = MEM_BASE + 64K, LENGTH = 1M - 64K }
MEMORY { readonly(r) : ORIGIN = MEM_BASE + 1M, LENGTH = 1M }
MEMORY { mem_rw(rw) : ORIGIN = MEM_BASE + 2M, LENGTH = 1M }
MEMORY { mem_16_rom(r) : ORIGIN = APPLE2_ROMS, LENGTH = 64K }
ENTRY(_start)

PROVIDE( __thread_stacks_start = MEM_BASE + 8M );
PROVIDE( __thread_stacks_end = APPLE2_ROMS );
PROVIDE( __trap_stack_end = MEM_BASE + 64K );
SECTIONS
{
    .text : ALIGN(16) {
        start.o (.text*)
        * (.text*)
    } >exe
    .init_array : ALIGN(4) {
        __init_array_start = .;
        * (.init_array.00000)
        * (.init_array*)
        __init_array_end = .;
    } >readonly
    .fini_array : ALIGN(4) {
        * (.fini_array)
    } >readonly

    .got : ALIGN(4) {
        *(.got)
    } >readonly

    .got.plt : ALIGN(4) {
        *(.got.plt)
    } >readonly

    .rodata : ALIGN(16) {
        *(.rodata*)
    } >readonly

    # Must be last section in the read only memory
    # All s* sections need to be grouped together.
    .srodata : ALIGN(16) {
        #. = 1M - SIZEOF(THIS SECTION);
        *(.srodata*)
    } >readonly

    .sdata : ALIGN(16) {
        __global_pointer$ = . + 2K;
         *(.sdata*)
    } >mem_rw

    .sbss : ALIGN(16) {
        * (.sbss*)
    } >mem_rw

    .bss : ALIGN(16) {
        * (.bss*)
    } >mem_rw

    .data : ALIGN(16) {
         *(.data*)
    } >mem_rw

    .apple2_rom : {
        . = 0xd000;     # ROM start address in 16bit address space
        __apple2_rom = .;
        Apple2*_rom.o (.apple2_rom);
    } >mem_16_rom

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
    .rela.text : { *(.rela.text*) }

    .riscv.attributes : { *(.riscv.attributes) }
    .comment : { *(.comment) }
}
