#pragma once

#include <cstddef>
#include <cstdint>

static inline void fence() {
    asm volatile("" ::: "memory");
}

static inline void rrb() {
    fence();
}

static inline void rwb() {
    fence();
}

static inline void wrb() {
    fence();
}

static inline void wwb() {
    fence();
}

void clrmem(uint32_t *ptr, size_t size);

template <typename T>
T readUnaligned(const T &src) {
    auto srcPtr = reinterpret_cast<const uint8_t *>(&src);

    T result = 0;
    for( unsigned i=0; i<sizeof(T); ++i ) {
        result <<= 8;
        result |= srcPtr[i];
    }

    return result;
}
