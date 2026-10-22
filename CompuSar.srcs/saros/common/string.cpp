#include <string.h>

#include <stdint.h>

extern "C" __attribute__((used, externally_visible,
                          optimize("no-tree-loop-distribute-patterns")))
void *   memcpy (void *__restrict dst, const void *__restrict src, size_t size)
{
    while(size!=0) {
        size--;
        reinterpret_cast<uint8_t *>(dst)[size] = reinterpret_cast<const uint8_t *>(src)[size];
    }

    return dst;
}

extern "C" __attribute__((used, externally_visible,
                          optimize("no-tree-loop-distribute-patterns")))
void *memset (void *__s, int __c, size_t __n) {
    auto dst = reinterpret_cast<uint8_t *>(__s);
    while( __n > 0 ) {
        *dst = __c;
        __n--;
        dst++;
    }

    return __s;
}
