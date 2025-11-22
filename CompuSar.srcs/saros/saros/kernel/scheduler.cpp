#include <saros/kernel/scheduler.h>

#include <saros/saros.h>
#include <irq.h>

namespace Saros::Kernel {

namespace {

extern "C"
void switchOutCoop();

// With no nested traps, we effectively don't use the MPIE bit in mstatus (will always be 0), and so switchIn is the same for the
// Cooporative and IRQ flows.
extern "C"
[[noreturn]] void switchIn(Thread *);

}

static constexpr size_t ThreadClassSizeInt = ( sizeof(Thread) + sizeof(uint32_t) - 1 ) / sizeof(uint32_t);

Thread *getCurrentThread() {
    Thread *current;

    asm ("mv %0, tp": "=r"(current));

    return current;
}

[[noreturn]] static void idleLoop(void *) noexcept {
    while(true)
        wfi();
}

void Scheduler::init( std::span<ThreadStack> stackArea ) {
    assertWithMessage( ! _threadStackAllocator.has_value(), "Saros::Scheduler::init called twice" );
    _threadStackAllocator.emplace( stackArea );

    // Reset any waiting counters
    reset_timer_cycles();
    Thread *idleThread = createThread( idleLoop, nullptr, false );

    // There's no need to lock, as interrupts have not yet been enabled
    idleThread->_listHook.unlink();
    idleThread->_priority = 2;   // The only thread with priority 2
    _readyThreads[idleThread->_priority].push_back(*idleThread);
}

Thread *Scheduler::createThread( Entrypoint function, void *param, bool highPriority ) {
    assertWithMessage( _threadStackAllocator.has_value(), "Saros::Scheduler::createThread called without init" );

    auto newStack = _threadStackAllocator->alloc();

    uint32_t *stackTop = &newStack->back() - ThreadClassSizeInt;
    Thread *thread = new (stackTop) Thread(this, stackTop, std::move(newStack), function, param);

    if( highPriority )
        thread->_priority = 0;
    else
        thread->_priority = 1;

    thread->setState(Thread::State::Ready);
    SpinLock lock{true};   // RAII object auto-releases at function end
    _readyThreads[thread->_priority].push_back(*thread);

    return thread;
}

void Scheduler::stopThread() {
    SpinLock locker{true};

    Thread *currentThread = getCurrentThread();
    currentThread->_listHook.unlink();
    currentThread->_state = Thread::State::Dead;
    currentThread->~Thread();

    asm volatile("csrr sp, mscratch; mv tp, zero");
    rescheduleImpl();
}

void Scheduler::run( Thread *thread ) {
    switchIn( thread );
}

void Scheduler::sleepOn( ThreadQueue &queue ) {
    csr_read_clr_bits<CSR::mstatus>( MSTATUS__MIE );

    Thread *currentThread = getCurrentThread();

    assertWithMessage( currentThread->getState() == Thread::State::Ready, "Running thread is not in state Ready" );
    currentThread->_listHook.unlink();
    currentThread->setState( Thread::State::Sleeping );
    queue.push_back( *currentThread );

    switchOutCoop();
}

void Scheduler::schedule( Thread *thread ) {
    assertWithMessage( thread->getState() != Thread::State::Ready, "Trying to schedule a thread that is already Ready" );

    thread->_listHook.unlink();
    thread->setState( Thread::State::Ready );
    _readyThreads[thread->_priority].push_back( *thread );
}

[[noreturn]] void Scheduler::reschedule() {
    saros._scheduler.rescheduleImpl();
}

[[noreturn]] void Scheduler::rescheduleImpl() {
    Thread *current = getCurrentThread();

    if( current!=nullptr && current->getState() == Thread::State::Ready ) {
        for( unsigned i = 0; i < current->_priority; ++i ) {
            if( !_readyThreads[i].empty() ) {
                switchIn( &_readyThreads[i].front() );
            }
        }

        // Currently running thread is our best candidate
        switchIn( current );
    } else {
        for( unsigned i = 0; i < NumPriorities; ++i ) {
            if( !_readyThreads[i].empty() ) {
                switchIn( &_readyThreads[i].front() );
            }
        }

        abortWithMessage("Ready queue is completely empty");
    }
}

} // namespace Saros::Kernel
