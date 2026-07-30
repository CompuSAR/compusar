#include "uart.h"
#include "irq.h"
#include "format.h"

#include <saros/kernel/timer.h>
#include <saros/kernel/thread_stack.h>
#include <saros/fs/filesystem.h>

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

extern "C"
int saros_main() {
    // Run "pre main" functions
    for( auto ptr = __init_array_start; ptr != &__init_array_end; ++ptr )
        (*ptr)();

    uart_send("Second stage!\n");

    saros.init(std::span<Saros::Kernel::ThreadStack>( Saros::Kernel::__thread_stacks_start, &Saros::Kernel::__thread_stacks_end ));
    saros.run( startup_function, nullptr, "Startup thread"_fs );
    uart_send("Saros exit\n");

    halt();
}

void startup_function(void *) noexcept {
    SD::init();

    start_8bit();
}

void  __attribute__((weak)) start_8bit() {
}
