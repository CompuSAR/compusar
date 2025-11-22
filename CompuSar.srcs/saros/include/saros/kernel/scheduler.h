#pragma once

#include <saros/kernel/thread.h>

#include <irq.h>

#include <optional>

namespace Saros::Kernel {

class Scheduler {
    static constexpr size_t NumPriorities = 3; // High, normal and idle
    friend Thread;
    friend void ::trap_handler();

    static constexpr size_t MaxNumThreads = 256;

    std::optional<ThreadStackAllocator> _threadStackAllocator;

    using ThreadQueueOption = boost::intrusive::member_hook<Thread, decltype(Thread::_listHook), &Thread::_listHook>;
public:
    using ThreadQueue = boost::intrusive::list<Thread, ThreadQueueOption, boost::intrusive::constant_time_size<false>>;
private:
    std::array<ThreadQueue, NumPriorities> _readyThreads;

public:

    void init( std::span<ThreadStack> stackArea );

    Thread *createThread( Entrypoint function, void *param, bool highPriority = false );

    void run( Thread *thread );

    void sleepOn( ThreadQueue &queue );
    void schedule( Thread *thread );
private:
    // Methods to be called by Thread
    [[noreturn]] void stopThread();

    // Static method called by context switch
    [[noreturn]] static void reschedule();
    [[noreturn]] void rescheduleImpl();
};

} // namespace Saros::Kernel
