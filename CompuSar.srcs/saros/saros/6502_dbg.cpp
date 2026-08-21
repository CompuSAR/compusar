#include <6502_dbg.hh>

#include <saros/saros.h>
#include <saros/sync/event.h>

#include "uart.h"
#include "format.h"
#include "reg.h"

constexpr uint32_t DeviceNum = 0x83;

constexpr uint32_t Dbg_Status = 0x0000;
    constexpr uint32_t Dbg_Status__Cont = 0x0001;
    constexpr uint32_t Dbg_Status__Halt = 0x0002;
    constexpr uint32_t Dbg_Status__SingleStep = 0x0004;
constexpr uint32_t Dbg_State  = 0x0004;

constexpr uint32_t Dbg_ReadRegA = 0x0010;
constexpr uint32_t Dbg_ReadRegX = 0x0014;
constexpr uint32_t Dbg_ReadRegY = 0x0018;
constexpr uint32_t Dbg_ReadRegS = 0x001c;
constexpr uint32_t Dbg_ReadRegP = 0x0020;

constexpr uint32_t NumBreakpoints = 4;

constexpr uint32_t Dbg_BreakPointBase = 0x8000;

static Saros::Sync::Event debug6502Halted;

static void debugger_loop(void *) noexcept {
    uart_send("Debugger thread started\n");

    while(true) {
        irq_external_unmask(IrqExt__6502Debug);
        debug6502Halted.wait();

        // Handle the debugger
        uint32_t state = reg_read_32(DeviceNum, Dbg_State);
        uart_send("DBG: addr:");
        print_hex(state & 0xffff);
        uart_send(" A:");
        print_hex( reg_read_32(DeviceNum, Dbg_ReadRegA ) );
        uart_send(" X:");
        print_hex( reg_read_32(DeviceNum, Dbg_ReadRegX ) );
        uart_send(" Y:");
        print_hex( reg_read_32(DeviceNum, Dbg_ReadRegY ) );
        uart_send(" S:");
        print_hex( reg_read_32(DeviceNum, Dbg_ReadRegS ) );
        uart_send(" P:");
        uint32_t regP = reg_read_32(DeviceNum, Dbg_ReadRegP );
        print_hex( regP );

        if( regP & 0x80 )
            uart_send(" N");
        else
            uart_send(" -");

        if( regP & 0x40 )
            uart_send("V");
        else
            uart_send("-");

        if( regP & 0x20 )
            uart_send("1");
        else
            uart_send("-");

        if( regP & 0x10 )
            uart_send("B");
        else
            uart_send("-");

        if( regP & 0x08 )
            uart_send("D");
        else
            uart_send("-");

        if( regP & 0x04 )
            uart_send("I");
        else
            uart_send("-");

        if( regP & 0x02 )
            uart_send("Z");
        else
            uart_send("-");

        if( regP & 0x01 )
            uart_send("C\n");
        else
            uart_send("-\n");

        reg_write_32(DeviceNum, Dbg_Status, Dbg_Status__Cont | Dbg_Status__SingleStep);

        debug6502Halted.clear();
    }
}

void init_debugger() {
    //set_breakpoint( 0, 0xfe5e, 0, 0 );

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
