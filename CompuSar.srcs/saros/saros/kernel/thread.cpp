#include <saros/kernel/thread.h>

#include <saros/kernel/scheduler.h>

#include <ds/pool.h>
#include <memory.h>

namespace Saros::Kernel {

Thread::Thread( Scheduler *scheduler, void *stack_top, ThreadStackAllocator::Ptr stackPtr, Entrypoint functionEntry, void *param ) :
    _stack( std::move(stackPtr) ),
    _scheduler( scheduler )
{
    static_assert( offsetof(Thread, _context)==0 );

    clrmem( reinterpret_cast<uint32_t *>(&_context), sizeof(Context)/sizeof(uint32_t) );
    _context.sp = stack_top;
    _context.pc = reinterpret_cast<void*>(threadTrampoline);
    _context.a0 = this;
    _context.a1 = reinterpret_cast<void*>(functionEntry);
    _context.a2 = param;

    push(nullptr);
    push(nullptr);
    push(nullptr);
    push(nullptr);
}

void Thread::threadTrampoline(Thread *self, Entrypoint functionEntry, void *param) {
    functionEntry(param);

    self->_scheduler->stopThread();
}

void Thread::push(uint32_t value) {
    auto sp = static_cast<uint32_t *>(_context.sp);
    *(--sp) = value;
    _context.sp = sp;
}

void Thread::push(Context::GenPtr value) {
    static_assert( sizeof(uint32_t) == sizeof(Context::GenPtr) );

    push( reinterpret_cast<uint32_t>(value) );
}

} // namespace saros::kernel
