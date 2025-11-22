#pragma once

#include <saros/kernel/scheduler.h>
#include <saros/kernel/thread.h>
#include <saros/spin_lock.h>

#include <mutex>

namespace Saros {

class Saros {
    Kernel::Scheduler _scheduler;
    bool _running = false;

    friend Kernel::Scheduler;

public:
    using Entrypoint = Kernel::Entrypoint;

    Saros() = default;

    Saros(const Saros &) = delete;
    Saros &operator=(const Saros &) = delete;

    void init( std::span<Kernel::ThreadStack> stackArea );
    void run( Kernel::Entrypoint startupThreadFunction, void *param );

    void createThread( Entrypoint function, void *param, bool highPriority = false ) {
        _scheduler.createThread( function, param, highPriority );
    }

    [[nodiscard]] bool isRunning() const {
        return _running;
    }

    // Send the current thread to sleep on the specific queue
    void sleepOn( Kernel::Scheduler::ThreadQueue &queue );
    // Wake one thread from the wait list
    void wakeOneThread( Kernel::Scheduler::ThreadQueue &queue );
    // Wake all threads on the list
    void wakeAllThreads( Kernel::Scheduler::ThreadQueue &queue );

    void enableSoftwareInterrupt() const {
        csr_read_set_bits<CSR::mie>( MIE__MSIE_MASK );
    }
    void disableSoftwareInterrupt() const {
        csr_read_clr_bits<CSR::mie>( MIE__MSIE_MASK );
    }

private:
    void initIrq();
};

} // namespace saros

extern Saros::Saros saros;
