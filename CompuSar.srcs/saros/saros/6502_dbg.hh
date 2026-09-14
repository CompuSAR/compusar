#pragma once

#include <saros/sync/event.h>
#include <saros/sync/signal.h>

#include <cstdint>

void init_debugger();

void irq_debug_6502();

constexpr uint8_t BP_WRITE = 0x1, BP_SYNC = 0x2, BP_MEMLOCK = 0x4, BP_VP = 0x8;

constexpr uint32_t NumBreakpoints = 4;
// There's a thread listening for bp 0. When that triggers, the thread will perform
// continous tracing of the execution
void set_breakpoint( uint8_t bp, uint16_t address, uint8_t state, uint8_t mask );
void dbg_cont( bool singlestep = false );

enum class DbgReg { A, X, Y, S, P };
uint8_t dbg_readReg( DbgReg reg );

// Listen on the relevant event to be notified when the BP triggers.
extern Saros::Sync::Event dbg6502Bp[NumBreakpoints];
extern Saros::Sync::Signal dbg6502Halted;
