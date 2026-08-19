#include <6502_dbg.hh>

#include <saros/saros.h>
#include <saros/sync/event.h>

#include "uart.h"
#include "format.h"
#include "reg.h"

constexpr uint32_t DeviceNum = 0x83;

constexpr uint32_t Dbg_Status = 0x0000;
constexpr uint32_t Dbg_State  = 0x0004;
constexpr uint32_t NumBreakpoints = 4;

constexpr uint32_t Dbg_BreakPointBase = 0x8000;

static Saros::Sync::Event debug6502Halted;

static void debugger_loop(void *) noexcept {
    uart_send("Debugger thread started\n");

    set_breakpoint( 0, 0xfe5e, 0, 0 );
    while(true) {
        debug6502Halted.wait();

        // Handle the debugger
        uint32_t state = reg_read_32(DeviceNum, Dbg_State);
        uart_send("DBG: ");
        print_hex(state);
        uart_send("\n");

        debug6502Halted.clear();
        irq_external_unmask(IrqExt__6502Debug);
    }
}

void init_debugger() {
    saros.createThread( debugger_loop, nullptr, "Debugger thread"_fs );
}

void irq_debug_6502() {
    irq_external_mask(IrqExt__6502Debug);
    debug6502Halted.set();
}

void set_breakpoint( uint8_t bp, uint16_t address, uint8_t state, uint8_t mask ) {
    reg_write_32(
            DeviceNum, Dbg_BreakPointBase + bp * 4,
            mask<<28 | state<<24 | address );
}
