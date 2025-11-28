#pragma once

#include <saros/kernel/thread_queue.h>

namespace Saros::Sync {

class Signal {
    Kernel::ThreadQueue _threadQueue;

public:
    Signal() = default;
    Signal( const Signal & ) = delete;
    Signal &operator=( const Signal & ) = delete;

    void wait() {
        _threadQueue.sleep();
    }

    void signal() {
        _threadQueue.wakeAll();
    }
};

} // namespace Saros::Sync
