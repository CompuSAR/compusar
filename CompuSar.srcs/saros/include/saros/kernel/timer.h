#pragma once

#include <saros/sync/event.h>

#include <cstdint>

namespace Saros {

namespace Kernel { class TimerEvent; }

class TimerHandle {
    Kernel::TimerEvent *_event;

public:
    explicit TimerHandle(Kernel::TimerEvent *event = nullptr) : _event(event) {}

    TimerHandle(const TimerHandle &that) = delete;
    TimerHandle &operator=(const TimerHandle &that) = delete;
    TimerHandle(TimerHandle &&that) : _event(that._event) {
        that._event = nullptr;
    }

    TimerHandle &operator=(TimerHandle &&that) {
        if( &that != this ) {
            clear();
            _event = that._event;
            that._event = nullptr;
        }

        return *this;
    }

    ~TimerHandle() {
        clear();
    }

    Sync::Event &event() const;

    void clear();
};

typedef bool (*TimerCallback)(void *); 

[[nodiscard]] TimerHandle registerTimer(uint64_t triggerTime, uint64_t repeatDuration = 0);
[[nodiscard]] TimerHandle registerTimerNs(uint64_t triggerTime, uint64_t repeatDuration = 0);

} // namespace Saros::Kernel
