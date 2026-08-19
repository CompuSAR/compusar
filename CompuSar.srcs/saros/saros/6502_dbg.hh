#pragma once

#include <cstdint>

void init_debugger();

void irq_debug_6502();

constexpr uint8_t BP_WRITE = 0x1, BP_SYNC = 0x2, BP_MEMLOCK = 0x4, BP_VP = 0x8;
void set_breakpoint( uint8_t bp, uint16_t address, uint8_t state, uint8_t mask );
