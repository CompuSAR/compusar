#include <string.h>

#include <stdint.h>

void *   memcpy (void *__restrict dst, const void *__restrict src, size_t size) {
    while(size!=0) {
        size--;
        reinterpret_cast<uint8_t *>(dst)[size] = reinterpret_cast<const uint8_t *>(src)[size];
    }

    return dst;
}
