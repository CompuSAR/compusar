#include "dbglogger.hh"

#include "reg.h"
#include "uart.h"
#include "format.h"

static constexpr uint32_t DeviceId = 16;

static constexpr uint32_t SetReadAddr = 0x0000;

static constexpr uint32_t GetEndPtr = 0x0000;
static constexpr uint32_t GetAddrMask = 0x0004;
static constexpr uint32_t GetData0 = 0x0010;

static void dump_line(uint32_t ptr) {
    reg_write_32(DeviceId, SetReadAddr, ptr);
    uart_send("  ");
    print_dec(ptr);
    uart_send("  PC: ");
    print_hex(reg_read_32(DeviceId, GetData0));
    uart_send("\n");
}

void dumpdbglogger() {
    uint32_t endptr = reg_read_32(DeviceId, GetEndPtr);
    bool looped = endptr&0x80000000;
    endptr &= 0x7fffffff;
    const uint32_t addrMask = reg_read_32(DeviceId, GetAddrMask);

    uart_send("Dumping debug log:\n");
    print_dec(endptr);
    uart_send("  M ");
    print_hex(addrMask);
    uart_send("\n");

    uint32_t ptr = endptr;
    if( looped ) {
        uart_send("middle\n");
        while(ptr!=0) {
            dump_line(ptr);
            ptr = (ptr + 1) & addrMask;
        }
    }

    uart_send("start\n");
    ptr = 0;
    while(ptr!=endptr) {
        dump_line(ptr);
        ptr = (ptr + 1) & addrMask;
    }

    uart_send("Dumped\n\n");
}
