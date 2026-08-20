#pragma once

#include <saros/csr.h>
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
            // Disable interrupts
            bool prevIntState = (csr_read_clr_bits<CSR::mstatus>( MSTATUS__MIE ) & MSTATUS__MIE) != 0;
            csr_read_clr_bits<CSR::mstatus>( MSTATUS__MIE );

            // Check again that we're not set
            if( isSet() ) {
                if( prevIntState )
                    // Restore interrupts
                    csr_read_set_bits<CSR::mstatus>( MSTATUS__MIE );

                return;
            }

            // Sleep while interrupts are disabled. The sleep itself will re-enable them.
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
