MEM_BASE = 0x80000000;

MEMORY { preload(rwx) : ORIGIN = MEM_BASE, LENGTH = 256K }
ENTRY(_start)

SECTIONS
{
    .text : AT(0) {
        testprog.o (.text*)
    } >preload
}
