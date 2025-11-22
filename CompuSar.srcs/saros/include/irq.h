#pragma once

#include <stdint.h>

void sleep_ns(uint64_t nanoseconds);
void sleep_cycles(uint64_t cycles);
void wfi();
[[noreturn]] void halt();

uint32_t get_clock_freq();
uint64_t get_cycles_count();

void set_timer_ns(uint64_t nanoseconds);
void set_timer_cycles(uint64_t cycle_num);
void reset_timer_cycles();

#ifdef SAROS

static constexpr uint32_t IrqExt__UartTxReady = 0x00000001;
static constexpr uint32_t IrqExt__UartRxReady = 0x00000002;

void irq_external_mask( uint32_t mask );
void irq_external_unmask( uint32_t mask );

extern "C"
[[noreturn]] void trap_handler();

extern void handleSoftwareInterrupt();

#endif
