#pragma once

#include <saros/kernel/thread_queue.h>

namespace Saros::Sync {

class Event {
    Kernel::ThreadQueue _threadQueue;
    volatile bool _active = false;

public:
    Event() = default;
    Event( const Event & ) = delete;
    Event &operator=( const Event & ) = delete;

    void wait() {
        if( !isSet() ) {
            _threadQueue.sleep();
        }
    }

    void set() {
        _active = true;
        _threadQueue.wakeAll();
    }

    void clear() {
        _active = false;
    }

    [[nodiscard]] bool isSet() const {
        return _active;
    }
};

} // namespace Saros::Sync
