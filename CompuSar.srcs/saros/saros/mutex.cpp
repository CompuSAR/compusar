#include <saros/sync/mutex.h>

#include <saros/spin_lock.h>
#include <memory.h>

namespace Saros::Sync {

void Mutex::lock() {
    while( true ) {
        if( _locked ) {
            _threadQueue.sleep();
        } else {
            SpinLock irqDisabler(true);

            wrb();

            // We need to check again after disabling interrupts, as there might have been preemption.
            if( !_locked ) {
                _locked = true;

                return;
            }
        }
    }
}

bool Mutex::try_lock() {
    SpinLock irqDisabler(true);
    bool locked = !_locked;
    _locked = true;

    return locked;
}

void Mutex::unlock() {
    SpinLock irqDisabler(true);

    // TODO consider not setting the value to false, and  instead just calling wakeOne?
    _locked = false;

    _threadQueue.wakeOne();
}

} // namespace Saros::Sync
