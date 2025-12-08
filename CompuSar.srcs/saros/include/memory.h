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
