#include "saros/kernel/timer.h"

#include <saros/spin_lock.h>
#include <ds/pool.h>

#include "irq.h"

#include <boost/intrusive/list.hpp>

namespace Saros {
namespace Kernel {

struct TimerEvent {
    uint64_t wakeupTime;
    uint64_t repeatTime;
    Sync::Event wakeupEvent;
    boost::intrusive::list_member_hook< boost::intrusive::link_mode<boost::intrusive::auto_unlink> > listHook;
};

namespace {

constexpr size_t MaxTimers = 10;

using TimerQueueOption = boost::intrusive::member_hook<TimerEvent, decltype(TimerEvent::listHook), &TimerEvent::listHook>;
using TimerQueue = boost::intrusive::list<TimerEvent, TimerQueueOption, boost::intrusive::constant_time_size<false>>;

TimerQueue timerQueue;

}

static void placeTimerEvent(TimerEvent &event) {
    // Interrupts should be disabled at this point
    auto iter = timerQueue.begin();

    while( iter!=timerQueue.end() && iter->wakeupTime <= event.wakeupTime )
        ++iter;

    if( iter==timerQueue.end() ) {
        timerQueue.push_back(event);
    } else {
        timerQueue.insert(iter, event);
    }
}

static DS::PoolAllocator<TimerEvent, MaxTimers> timersAllocator;


} // namespace Saros::Kernel

using namespace Kernel;

void TimerHandle::clear() {
    if( _event != nullptr ) {
        SpinLock lock(true);
        timersAllocator.free(_event);
    }
}

Sync::Event &TimerHandle::event() const {
    return _event->wakeupEvent;
}

TimerHandle registerTimer(uint64_t triggerTime, uint64_t repeatDuration) {
    SpinLock lock(true);

    auto eventPtr = timersAllocator.alloc();

    eventPtr->wakeupTime = triggerTime;
    eventPtr->repeatTime = repeatDuration;

    bool first = timerQueue.empty() || timerQueue.front().wakeupTime > triggerTime;
    placeTimerEvent(*eventPtr);

    if( first ) {
        set_timer_cycles( triggerTime );
    }

    // TODO: Ptr is now movable. That would be better semantics
    return TimerHandle(eventPtr.release());
}

TimerHandle registerTimerNs(uint64_t triggerTime, uint64_t repeatDuration) {
    const uint64_t now = get_cycles_count();
    const uint64_t clockFreq = get_clock_freq();

    static constexpr uint64_t NanoFactor = 1'000'000'000;
    return registerTimer( now + triggerTime * clockFreq / NanoFactor, repeatDuration * clockFreq / NanoFactor  );
}

} // namespace Saros

using namespace Saros::Kernel;

void handleTimerInterrupt() {
    // No need to lock, as we're running with disabled interrupts
    uint64_t now = get_cycles_count();

    while( !timerQueue.empty() ) {
        TimerEvent &front = timerQueue.front();

        if( front.wakeupTime > now )
            break;

        timerQueue.pop_front();
        front.wakeupEvent.set();

        if( front.repeatTime!=0 ) {
            front.wakeupTime += front.repeatTime;
            placeTimerEvent(front);
        }
    }

    if( timerQueue.empty() ) {
        reset_timer_cycles();
    } else {
        set_timer_cycles(timerQueue.front().wakeupTime);
    }
}
