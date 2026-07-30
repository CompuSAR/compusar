#include <saros/kernel/scheduler.h>
#include <saros/kernel/thread_stack.h>
#include <saros/csr.h>

#include "display.h"
#include "format.h"
#include "irq.h"
#include "memory.h"
#include "reg.h"
#include "sd.h"
#include "uart.h"
#include "dbglogger.hh"

#define DEVICE_NUM 3

#define REG_HALT                0x0000
#define REG_CPU_CLOCK_FREQ      0x0004
#define REG_CYCLE_COUNT         0x0008
#define REG_WAIT_COUNT          0x0010
#define REG_INT_CYCLE           0x0200
#define REG_RESET_INT_CYCLE     0x0210
#define REG_RESET_WAIT_CYCLE    0x0214

#define REG_ACTIVE_IRQS         0x0400
#define REG_IRQ_MASK_SET        0x0500
#define REG_IRQ_MASK_CLEAR      0x0580


using namespace Saros;

#if 0
// These functions are intentionally left undefined, as they should never be used. Use Saros::sleep_ns instead
void sleep_ns(uint64_t nanoseconds) {
    sleep_cycles(nanoseconds*reg_read_32(DEVICE_NUM, REG_CPU_CLOCK_FREQ) / 1'000'000'000);
}

void sleep_cycles(uint64_t cycles) {
    uint64_t cycle_count = get_cycles_count();
    reg_write_64(DEVICE_NUM, REG_WAIT_COUNT, cycle_count + cycles);
    reg_read_32(DEVICE_NUM, REG_HALT);
}
#endif

void set_timer_ns(uint64_t nanoseconds) {
    set_timer_cycles(get_cycles_count() + nanoseconds*get_clock_freq() / 1'000'000'000);
}

void set_timer_cycles(uint64_t cycles_num) {
    reg_write_32(DEVICE_NUM, REG_INT_CYCLE+4, cycles_num>>32);
    wwb();
    reg_write_32(DEVICE_NUM, REG_INT_CYCLE, cycles_num & 0xffffffff);
}

void reset_timer_cycles() {
    reg_write_32(DEVICE_NUM, REG_RESET_INT_CYCLE, 0);
}

uint32_t get_clock_freq() {
    return reg_read_32(DEVICE_NUM, REG_CPU_CLOCK_FREQ);
}

uint64_t get_cycles_count() {
    uint64_t cycles_count = reg_read_32(DEVICE_NUM, REG_CYCLE_COUNT);
    rrb();
    cycles_count |= static_cast<uint64_t>( reg_read_32(DEVICE_NUM, REG_CYCLE_COUNT+4) )<<32;

    return cycles_count;
}

void wfi() {
    reg_write_32(DEVICE_NUM, REG_RESET_WAIT_CYCLE, 0);
    reg_read_32(DEVICE_NUM, REG_HALT);
}

void halt() {
    while( true ) {
        reg_write_64(DEVICE_NUM, REG_WAIT_COUNT, 0xffff'ffff'ffff'ffff);
        wfi();
    }
}

void __attribute__((weak)) handleSoftwareInterrupt() {
    abortWithMessage("handleSoftwareInterrupt is unimplemented");
}

void handleTimerInterrupt();

static void handleExternalInterrupt() {
    uint32_t active_irqs = reg_read_32( DEVICE_NUM, REG_ACTIVE_IRQS );

    if( (active_irqs & IrqExt__UartTxReady) != 0 )
        handle_uart_tx_ready_irq();
    if( (active_irqs & IrqExt__UartRxReady) != 0 )
        handle_uart_rx_ready_irq();
    if( (active_irqs & IrqExt__Vsync) != 0 )
        Display::handle_vsync_irq();
    if( (active_irqs & IrqExt__SdCardIn) != 0 )
        SD::irq_handler_insert();
    if( (active_irqs & IrqExt__SdCardDataIdle) != 0 )
        SD::irq_handler_data();
}

[[noreturn]] static void handle_trap(uint32_t cause) {
    dbglogger_stop();

    uint32_t tp;
    asm(" mv %0, tp":"=r"(tp));

    uart_sync_flush_buffer();

    uart_sync_message("\n\nTRAP detected. Cause 0x");
    print_hex(cause, true);
    uart_sync_message(" PC 0x");
    print_hex( csr_read<CSR::mepc>(), true );
    uart_sync_message(" Trap value 0x");
    print_hex( csr_read<CSR::mtval>(), true );
    uart_sync_message(" Thread 0x");
    print_hex(tp, true);
    uart_sync_message("\n");
    switch(cause) {
    case 0:
        uart_sync_message("Instruction address misaligned\n");
        break;
    case 1:
        uart_sync_message("Instruction access fault\n");
        break;
    case 2:
        uart_sync_message("Illegal instruction\n");
        break;
    case 3:
        uart_sync_message("Breakpoint\n");
        break;
    case 4:
        uart_sync_message("Load address misaligned\n");
        break;
    case 5:
        uart_sync_message("Load access fault\n");
        break;
    case 6:
        uart_sync_message("Store/AMO address misaligned\n");
        break;
    case 7:
        uart_sync_message("Store/AMO access fault\n");
        break;
    case 11:
        uart_sync_message("Environment call from M-mode\n");
        break;
    case 12:
        uart_sync_message("Instruction page fault\n");
        break;
    case 13:
        uart_sync_message("Load page fault\n");
        break;
    case 15:
        uart_sync_message("Store/AMO page fault\n");
        break;
    }

    using namespace Kernel;

    // Make sure that the thread pointer makes sense
    auto threadPtr = reinterpret_cast<const Thread *>(tp);
    const void *tpp = threadPtr;

    if( tpp>=&__thread_stacks_end || tpp<__thread_stacks_start ) {
        uart_sync_message("Thread pointer out of range\n");

        halt();
    }

    uart_sync_message("\nThread state:\n");

    auto context = threadPtr->getContext();

    uart_sync_message(" ra: ");
    print_hex(context.ra, true);
    uart_sync_message(" sp: ");
    print_hex(context.sp, true);
    uart_sync_message(" t0: ");
    print_hex(context.t0, true);
    uart_sync_message(" t1: ");
    print_hex(context.t1, true);
    uart_sync_message(" t2: ");
    print_hex(context.t2, true);

    uart_sync_message("\n s0: ");
    print_hex(context.s0, true);
    uart_sync_message(" s1: ");
    print_hex(context.s1, true);
    uart_sync_message(" a0: ");
    print_hex(context.a0, true);
    uart_sync_message(" a1: ");
    print_hex(context.a1, true);

    uart_sync_message("\n a2: ");
    print_hex(context.a2, true);
    uart_sync_message(" a3: ");
    print_hex(context.a3, true);
    uart_sync_message(" a4: ");
    print_hex(context.a4, true);
    uart_sync_message(" a5: ");
    print_hex(context.a5, true);

    uart_sync_message("\n a6: ");
    print_hex(context.a6, true);
    uart_sync_message(" a7: ");
    print_hex(context.a7, true);
    uart_sync_message(" s2: ");
    print_hex(context.s2, true);
    uart_sync_message(" s3: ");
    print_hex(context.s3, true);

    uart_sync_message("\n s4: ");
    print_hex(context.s4, true);
    uart_sync_message(" s5: ");
    print_hex(context.s5, true);
    uart_sync_message(" s6: ");
    print_hex(context.s6, true);
    uart_sync_message(" s7: ");
    print_hex(context.s7, true);

    uart_sync_message("\n s8: ");
    print_hex(context.s8, true);
    uart_sync_message(" s9: ");
    print_hex(context.s9, true);
    uart_sync_message(" s10: ");
    print_hex(context.s10, true);
    uart_sync_message(" s11: ");
    print_hex(context.s11, true);

    uart_sync_message("\n t3: ");
    print_hex(context.t3, true);
    uart_sync_message(" t4: ");
    print_hex(context.t4, true);
    uart_sync_message(" t5: ");
    print_hex(context.t5, true);
    uart_sync_message(" t6: ");
    print_hex(context.t6, true);

    uart_sync_message("\nThread name: ");
    uart_sync_message(threadPtr->getName());
    uart_sync_message("\n");

    static_assert( (ThreadStackSize & -ThreadStackSize) == ThreadStackSize, "Thread stack size is not a power of 2" );
    static constexpr uint32_t StackSizeMask = ~ (ThreadStackSize - 1);
    if( (reinterpret_cast<uint32_t>(context.sp) & StackSizeMask) != (tp &  StackSizeMask) )  {
        uart_sync_message("Stack pointer and thread pointer aren't on the same thread!\n");

        halt();
    }

    if( reinterpret_cast<uint32_t>(context.sp) % sizeof(uint32_t) != 0 ) {
        uart_sync_message("Stack pointer not aligned\n");

        halt();
    }

    uart_sync_message("Dumping stack:\n");
    uint32_t sp = reinterpret_cast<uint32_t>(context.sp);
    while( sp < tp ) {
        uart_sync_message("  ");
        print_hex(sp, true);
        uart_sync_message(":");
        do {
            uart_sync_message("  ");
            print_hex( *reinterpret_cast<const uint32_t *>(sp), true );
            sp += sizeof(uint32_t);
        } while( sp % 16 != 0 && sp < tp );
        uart_sync_message("\n");
    }

    halt();
}

extern "C"
[[noreturn]] void trap_handler() {
    uint32_t cause = csr_read<CSR::mcause>();

    if( cause & 0x80000000 ) {
        // Interrupt
        switch( cause & 0x7fffffff ) {
        case MIE__MSIE_BIT: handleSoftwareInterrupt(); break;
        case MIE__MTIE_BIT: handleTimerInterrupt(); break;
        case MIE__MEIE_BIT: handleExternalInterrupt(); break;
        default: // TODO handle invalid case
                            ;
        }
    } else {
        handle_trap(cause);
    }

    Saros::Kernel::Scheduler::reschedule();
}

void irq_external_mask( uint32_t mask ) {
    reg_write_32( DEVICE_NUM, REG_IRQ_MASK_SET, mask );
}

void irq_external_unmask( uint32_t mask ) {
    reg_write_32( DEVICE_NUM, REG_IRQ_MASK_CLEAR, mask );
}
