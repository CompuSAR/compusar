#include "uart.h"
#include "irq.h"
#include "format.h"

#include <saros/kernel/timer.h>

#include "assets/logo.h"
#include "display.h"
#include "gpio.h"
#include "sd.h"

#include <saros/csr.h>
#include <saros/saros.h>
#include <8bit_hook.h>

extern void startup_function(void *) noexcept;
extern "C" void (*__init_array_start[])();
extern "C" void (*__init_array_end)();

extern "C" Saros::Kernel::ThreadStack __thread_stacks_start[], __thread_stacks_end;

extern "C"
int saros_main() {
    // Run "pre main" functions
    for( auto ptr = __init_array_start; ptr != &__init_array_end; ++ptr )
        (*ptr)();

    uart_send("Second stage!\n");

    saros.init(std::span<Saros::Kernel::ThreadStack>( __thread_stacks_start, &__thread_stacks_end ));
    saros.run( startup_function, nullptr );
    uart_send("Saros exit\n");

    halt();
}

void logoCrawl(void *) noexcept {
    static constexpr uint16_t WIDTH = 640, HEIGHT = 480;
    uint16_t x=120, y=17;
    int dirx = 1, diry = 1;

    Display::setDisplay(Bitmaps::logo, x, y);
    reset_gpio_bits(0, GPIO0__DISPLAY32_RESET | GPIO0__DDR_RESET);

    irq_external_unmask( IrqExt__Vsync );

    while(true) {
        x+=dirx;
        y+=diry;

        if( x==WIDTH - Bitmaps::logo.width )
            dirx = -1;
        if( x==0 )
            dirx = 1;
        if( y==HEIGHT - Bitmaps::logo.height )
            diry = -1;
        if( y==0 )
            diry = 1;

        Display::vsyncSignal.wait();

        Display::setDisplay(Bitmaps::logo, x, y);
    }
}

static int timerId = 0;

void timerDemo(void *delayPtr) noexcept {
    int threadId = ++timerId;
    uint64_t delay = *reinterpret_cast<const uint64_t *>(delayPtr);

    Saros::TimerHandle timer = Saros::registerTimerNs( get_cycles_count() + delay, delay );

    uart_send("Timer thread ");
    print_hex(threadId);
    uart_send(" started\n");

    while(true) {
        timer.event().wait();
        timer.event().clear();

        uart_send("Timer ");
        print_hex(threadId);
        uart_send("\n");
    }
}

void startup_function(void *) noexcept {
    SD::init();

    static constexpr uint64_t delay1 = 1000000000, delay2 = 1333566645;

    saros.createThread( logoCrawl, nullptr );
    saros.createThread( timerDemo, (void*)&delay1 );
    saros.createThread( timerDemo, (void*)&delay2 );
    start_8bit();
}

void  __attribute__((weak)) start_8bit() {
}
