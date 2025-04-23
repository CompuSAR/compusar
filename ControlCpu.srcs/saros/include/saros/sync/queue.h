#pragma once

#include <p1c1.h>
#include <saros/sync/event.h>
#include <saros/spin_lock.h>

namespace Saros::Sync {

template <typename T, size_t BufferSize = 1024>
class Queue {
    P1C1<T, BufferSize> _queue;
    Event _hasItems, _hasRoom;

public:
    Queue() {
        _hasItems.clear();
        _hasRoom.set();
    }

    Queue(const Queue &) = delete;
    Queue &operator=(const Queue &) = delete;

    void push(T value) {
        while(true) {
            _hasRoom.wait();

            SpinLock lock(true);

            if( pushIrq(value) ) {
                return;
            }
        }
    }

    [[nodiscard]] bool pushIrq(T value) {
        if( _queue.isFull() ) {
            _hasRoom.clear();

            return false;
        }

        _queue.produce(value);
        _hasItems.set();

        return true;
    }

    [[nodiscard]] T pop() {
        while( true ) {
            _hasItems.clear();
            
            if( _queue.isEmpty() )
                _hasItems.wait();

            SpinLock lock(true);

            if( !_queue.isEmpty() ) {
                T ret = _queue.consume();
                _hasRoom.set();

                if( !_queue.isEmpty() )
                    _hasItems.set();

                return ret;
            }
        }
    }
};

} // namespace Saros::Sync
