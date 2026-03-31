#include "format.h"

#include "uart.h"

void print_hex(uint64_t number, bool sync) {
    static const char lookup[] = "0123456789abcdef";
    char buffer[16];
    int i=0;

    do {
        buffer[i++] = lookup[number&0xf];
        buffer[i++] = lookup[(number&0xf0) >> 4];

        number >>= 8;
    } while(number!=0);

    for( int j=i-1; j>=0; --j ) {
#ifdef SAROS
        if( sync )
            uart_send_raw(buffer[j]);
        else
#endif
            uart_send(buffer[j]);
    }
}

void print_dec(uint64_t number) {
    char buffer[25];
    int i=0;

    do {
        buffer[i++] = (number % 10) + '0';
        number /= 10;
    } while(number!=0);

    for( int j=i-1; j>=0; --j ) {
        uart_send(buffer[j]);
    }
}

void dump_memory(std::span<uint8_t> memory) {
    size_t i = 0;

    while( i<memory.size() ) {
        for( size_t j=0; j<16 && i<memory.size(); ++j, ++i ) {
            uart_send(" ");
            print_hex(memory[i]);
        }
        uart_send("\n");
    }
}
