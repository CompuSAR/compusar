#include <saros/kernel/thread_queue.h>

#include <saros/saros.h>

namespace Saros::Kernel {

void ThreadQueue::wakeOne() {
    saros.wakeOneThread( _queue );
}

void ThreadQueue::wakeAll() {
    saros.wakeAllThreads( _queue );
}

void ThreadQueue::sleep() {
    saros.sleepOn( _queue );
}

} // namespace Saros::Kernel
