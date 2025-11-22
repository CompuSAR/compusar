#pragma once

#include <saros/kernel/thread_stack.h>

#define BOOST_INTRUSIVE_SAFE_HOOK_DEFAULT_ASSERT(cond) assertWithMessage(cond, "Boost assert failed")
#include <boost/intrusive/list.hpp>

namespace Saros::Kernel {

class Scheduler;

class Thread {
    // Assembly code assumes this is the first element
    struct Context {
        using GenPtr = void *;
        GenPtr        ra,  sp,            t0,  t1,  t2,
                 s0,  s1,  a0,  a1,  a2,  a3,  a4,  a5,
                 a6,  a7,  s2,  s3,  s4,  s5,  s6,  s7,
                 s8,  s9,  s10, s11, t3,  t4,  t5,  t6;
        GenPtr   pc;
    } _context;
    static_assert( std::is_standard_layout_v<Context>, "Class Thread::Context must be standard layout" );
    static_assert( sizeof(Context) == 0x78, "Mismatch between C++ and assembly context sizes" );

    ThreadStackAllocator::Ptr _stack;
    Scheduler *_scheduler;
    boost::intrusive::list_member_hook< boost::intrusive::link_mode<boost::intrusive::auto_unlink> > _listHook;
    enum class State { Ready, Sleeping, Dead } _state = State::Dead;

    unsigned _priority = 1;

    friend Scheduler;
public:

    Thread( Scheduler *scheduler, void *stack_top, ThreadStackAllocator::Ptr stackPtr, Entrypoint functionEntry, void *param );
    Thread( const Thread & ) = delete;
    Thread &operator=( const Thread & ) = delete;

private:
    [[noreturn]] static void threadTrampoline(Thread *self, Entrypoint functionEntry, void *param);

    void push(uint32_t value);
    void push(Context::GenPtr value);

    // For use by the scheduler
    void setState( State state ) {
        _state = state;
    }
    State getState() const {
        return _state;
    }
};

} // namespace Saros::Kernel
