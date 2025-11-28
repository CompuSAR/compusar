#include <saros/kernel/scheduler.h>
#include <saros/csr.h>

#include "display.h"
#include "format.h"
#include "irq.h"
#include "memory.h"
#include "reg.h"
#include "uart.h"

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

void sleep_ns(uint64_t nanoseconds) {
    sleep_cycles(nanoseconds*reg_read_32(DEVICE_NUM, REG_CPU_CLOCK_FREQ) / 1'000'000'000);
}

void sleep_cycles(uint64_t cycles) {
    uint64_t cycle_count = reg_read_64(DEVICE_NUM, REG_CYCLE_COUNT);
    reg_write_64(DEVICE_NUM, REG_WAIT_COUNT, cycle_count + cycles);
    reg_read_32(DEVICE_NUM, REG_HALT);
}

void set_timer_ns(uint64_t nanoseconds) {
    set_timer_cycles(get_cycles_count() + nanoseconds*get_clock_freq() / 1'000'000'000);
}

void set_timer_cycles(uint64_t cycles_num) {
    reg_write_32(DEVICE_NUM, REG_INT_CYCLE+1, cycles_num>>32);
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
    cycles_count |= static_cast<uint64_t>( reg_read_32(DEVICE_NUM, REG_CYCLE_COUNT+1) )<<32;

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

static void handleTimerInterrupt() {
    // TODO implement
    reset_timer_cycles();
}

static void handleExternalInterrupt() {
    uint32_t active_irqs = reg_read_32( DEVICE_NUM, REG_ACTIVE_IRQS );

    if( (active_irqs & IrqExt__UartTxReady) != 0 )
        handle_uart_tx_ready_irq();
    if( (active_irqs & IrqExt__UartRxReady) != 0 )
        handle_uart_rx_ready_irq();
    if( (active_irqs & IrqExt__Vsync) != 0 )
        Display::handle_vsync_irq();
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
        // Trap
        uart_sync_flush_buffer();

        uart_sync_message("\n\nTRAP detected. Cause 0x");
        print_hex(cause, true);
        uart_sync_message(" PC 0x");
        print_hex( csr_read<CSR::mepc>(), true );
        uart_sync_message(" Trap value 0x");
        print_hex( csr_read<CSR::mtval>(), true );
        uart_sync_message("\n");

        halt();
    }

    Saros::Kernel::Scheduler::reschedule();
}

void irq_external_mask( uint32_t mask ) {
    reg_write_32( DEVICE_NUM, REG_IRQ_MASK_SET, mask );
}

void irq_external_unmask( uint32_t mask ) {
    reg_write_32( DEVICE_NUM, REG_IRQ_MASK_CLEAR, mask );
}

