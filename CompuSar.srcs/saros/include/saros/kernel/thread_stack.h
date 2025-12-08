#pragma once

#include <ds/pool.h>

#include <array>
#include <cstddef>
#include <cstdint>

namespace Saros::Kernel {

static constexpr size_t ThreadStackSize = 32*1024;

class ThreadStack {
    uint32_t _stack[ThreadStackSize/sizeof(uint32_t)];

public:
    ThreadStack() {
        // Do NOT set this to =default, or placement new will call memset over the memory :-(
    }
    ThreadStack(const ThreadStack &) = delete;
    ThreadStack &operator=(const ThreadStack &) = delete;
    ThreadStack(const ThreadStack &&) = delete;
    ThreadStack &operator=(const ThreadStack &&) = delete;

    uint32_t &back() { return _stack[ThreadStackSize/sizeof(uint32_t) - 1]; }
};

using ThreadStackAllocator = DS::PoolAllocator<ThreadStack, 0>;

using Entrypoint = void(*)(void *) noexcept;

} // namespace Saros::Kernel
