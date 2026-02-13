#pragma once

#include <saros/sync/event.h>

#include <cstdint>

namespace Saros {

namespace Kernel { class TimerEvent; }

class TimerHandle {
    Kernel::TimerEvent *_event;

public:
    explicit TimerHandle(Kernel::TimerEvent *event) : _event(event) {}

    TimerHandle(const TimerHandle &that) = delete;
    TimerHandle &operator=(const TimerHandle &that) = delete;
    TimerHandle(const TimerHandle &&hat);
    TimerHandle &operator=(const TimerHandle &&that);

    ~TimerHandle();

    Sync::Event &event() const;
};

typedef bool (*TimerCallback)(void *); 

[[nodiscard]] TimerHandle registerTimer(uint64_t triggerTime, uint64_t repeatDuration = 0);
[[nodiscard]] TimerHandle registerTimerNs(uint64_t triggerTime, uint64_t repeatDuration = 0);

} // namespace Saros::Kernel
