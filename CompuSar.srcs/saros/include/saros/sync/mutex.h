#pragma once

#include <saros/kernel/thread_queue.h>

namespace Saros::Sync {

class Mutex {
    Kernel::ThreadQueue _threadQueue;
    bool _locked = false;

public:
    Mutex() = default;
    Mutex( const Mutex & ) = delete;
    Mutex &operator=( const Mutex & ) = delete;

    void lock();
    bool try_lock();
    void unlock();
};

} // namespace Saros::Sync
