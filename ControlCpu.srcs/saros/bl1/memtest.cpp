#include "memtest.h"

#include "abort.h"
#include "format.h"
#include "irq.h"
#include "uart.h"

#include <cstddef>

namespace {

extern "C" uint8_t TEXT_START[], TEXT_END[];
extern "C" size_t MEM_BASE[];
constexpr size_t CACHE_SIZE = 16*1024;
constexpr size_t MEM_SIZE = 32*1024*1024 / sizeof(size_t);

constexpr size_t PATTERN_INIT = 0xe263fe9c;
constexpr size_t PATTERN_MUL = 0x4c681767;

void fill_memory() {
    const size_t text_size = TEXT_END - TEXT_START;
    const size_t text_offset = reinterpret_cast<size_t>(&TEXT_START[0]) % CACHE_SIZE;

    uint32_t pattern = PATTERN_INIT;

    for(size_t offset = 0; offset < MEM_SIZE; offset++) {
        if( (offset%CACHE_SIZE) < text_offset || (offset%CACHE_SIZE) > (text_offset+text_size) )
            MEM_BASE[offset] = pattern;

        pattern *= PATTERN_MUL;
    }
}

void verify_memory() {
    const size_t text_size = TEXT_END - TEXT_START;
    const size_t text_offset = reinterpret_cast<size_t>(&TEXT_START[0]) % CACHE_SIZE;

    uint32_t pattern = PATTERN_INIT;

    for(size_t offset = 0; offset < MEM_SIZE; offset++) {
        if( (offset%CACHE_SIZE) < text_offset || (offset%CACHE_SIZE) > (text_offset+text_size) ) {
            size_t read = MEM_BASE[offset];
            if( read != pattern ) {
                uart_send("Pattern error at offset ");
                print_hex(offset);
                uart_send(". Expected ");
                print_hex(pattern);
                uart_send(". Found ");
                print_hex(read);
                uart_send("\n");
            }
        }

        pattern *= PATTERN_MUL;
    }
}

} // Anonymous namespace

void test_mem() {
    uart_send("Mem test:\n  Filling memory with test pattern\n");
    fill_memory();

    uart_send("  Verifying test pattern\n");
    verify_memory();

    uart_send("Mem test done\n\n");

    halt();
}
