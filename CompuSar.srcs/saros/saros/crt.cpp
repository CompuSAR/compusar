#include <memory.h>

void clrmem(uint32_t *ptr, size_t size) {
    while( size!=0 ) {
        *ptr = 0;
        ptr++;
        size--;
    }
}
