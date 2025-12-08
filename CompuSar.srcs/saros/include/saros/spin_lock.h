#pragma once

#include <saros/csr.h>

namespace Saros {

class SpinLock {
    bool _locked = false, _prevIntState;

public:
    SpinLock() = default;
    explicit SpinLock( bool locked ) : SpinLock() {
        if( locked )
            lock();
    }

    SpinLock( const SpinLock & ) = delete;
    SpinLock &operator=( const SpinLock & ) = delete;

    ~SpinLock() { if( _locked ) unlock(); }

    void lock() {
        assertWithMessage( !_locked, "SpinLock::lock called while already held" );
        _locked = true;
        _prevIntState = (csr_read_clr_bits<CSR::mstatus>( MSTATUS__MIE ) & MSTATUS__MIE) != 0;
    }

    void try_lock() {
        lock();
    }

    void unlock() {
        assertWithMessage( _locked, "SpinLock::unlock called without holding lock" );

        if( _prevIntState ) {
            uint32_t prevState = csr_read_set_bits<CSR::mstatus>( MSTATUS__MIE );

            assertWithMessage( (prevState & MSTATUS__MIE)==0, "SpinLock::unlock called with interrupts enabled" );
        }

        _locked = false;
    }
};

} // namespace Saros
