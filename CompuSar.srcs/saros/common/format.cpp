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

