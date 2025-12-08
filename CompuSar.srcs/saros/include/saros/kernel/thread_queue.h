#pragma once

#include <saros/kernel/scheduler.h>

namespace Saros::Kernel {

class ThreadQueue {
    Scheduler::ThreadQueue _queue;

public:

    void wakeOne();
    void wakeAll();

    void sleep();
};

} // namespace Saros::Kernel
