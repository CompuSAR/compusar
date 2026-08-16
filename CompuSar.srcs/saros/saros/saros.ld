# Linker script for Saros

MEM_BASE = 0x80000000;
PRELOAD_RESERVED = 64K;
MEM8BIT_START = MEM_BASE + 16M;

MEMORY { preload(rwx) : ORIGIN = MEM_BASE, LENGTH = PRELOAD_RESERVED }
MEMORY { discard : ORIGIN = 0x1000000, LENGTH = 0x1000000 }
MEMORY { error : ORIGIN = 0xf0000000, LENGTH = 0 }
MEMORY { exe(rx) : ORIGIN = MEM_BASE + PRELOAD_RESERVED, LENGTH = 1M - PRELOAD_RESERVED }
MEMORY { readonly(r) : ORIGIN = MEM_BASE + 1M, LENGTH = 1M }
MEMORY { mem_rw(rw) : ORIGIN = MEM_BASE + 2M, LENGTH = 1M }
MEMORY { mem_8_fw(r) : ORIGIN = MEM8BIT_START, LENGTH = 64K - 8K }
MEMORY { mem_8_rom(r) : ORIGIN = MEM8BIT_START+0xd000, LENGTH = 12K }
ENTRY(_start)

PROVIDE( __thread_stacks_start = MEM_BASE + 8M );
PROVIDE( __thread_stacks_end = MEM8BIT_START );
PROVIDE( __trap_stack_end = MEM_BASE + 64K );

PHDRS
{
    text        PT_LOAD;
    rom         PT_LOAD;
    rw          PT_LOAD;
    apple2_fw   PT_LOAD;
    apple2_rom  PT_LOAD;
}

SECTIONS
{
    .text : ALIGN(16) {
        start.o (.text*)
        * (.text*)
    } >exe :text
    .init_array : ALIGN(4) {
        __init_array_start = .;
        * (.init_array.00000)
        * (.init_array*)
        __init_array_end = .;
    } >readonly :rom
    .fini_array : ALIGN(4) {
        * (.fini_array)
    } >readonly :rom

    .got : ALIGN(4) {
        *(.got)
    } >readonly :rom

    .got.plt : ALIGN(4) {
        *(.got.plt)
    } >readonly :rom

    .rodata : ALIGN(16) {
        *(.rodata*)
    } >readonly :rom

    # Must be last section in the read only memory
    # All s* sections need to be grouped together.
    .srodata : ALIGN(16) {
        #. = 1M - SIZEOF(THIS SECTION);
        *(.srodata*)
    } >readonly :rom

    .sdata : ALIGN(16) {
        __global_pointer$ = . + 2K;
         *(.sdata*)
    } >mem_rw :rw

    .sbss (NOLOAD) : ALIGN(16) {
        * (.sbss*)
    } >mem_rw :rw

    .bss : ALIGN(16) {
        * (.bss*)
    } >mem_rw :rw

    .data : ALIGN(16) {
         *(.data*)
    } >mem_rw :rw

    .uninitialized (NOLOAD) : ALIGN(16) {
        *(.uninitialized)
    } >mem_rw :NONE

    .apple2_fw : {
        *_fw.o (.apple2_fw);
    } > mem_8_fw :apple2_fw

    .apple2_rom : {
        Apple2*_rom.o (.apple2_rom);
    } >mem_8_rom :apple2_rom

    /DISCARD/ : { *(.eh_frame) *(.note.GNU-stack) }

    .debug_info         0 : { *(.debug_info) } :NONE
    .debug_abbrev       0 : { *(.debug_abbrev) } :NONE
    .debug_loc          0 : { *(.debug_loc) } :NONE
    .debug_aranges      0 : { *(.debug_aranges) } :NONE
    .debug_line         0 : { *(.debug_line) } :NONE
    .debug_str          0 : { *(.debug_str) } :NONE
    .debug_ranges       0 : { *(.debug_ranges) } :NONE
    .debug_line_str     0 : { *(.debug_line_str) } :NONE
    .debug_loclists     0 : { *(.debug_loclists) } :NONE
    .debug_rnglists     0 : { *(.debug_rnglists) } :NONE
    .debug_frame        0 : { *(.debug_frame) } :NONE
    .rela.text : { *(.rela.text*) } :NONE

    .riscv.attributes : { *(.riscv.attributes) } :NONE
    .comment : { *(.comment) } :NONE
}
