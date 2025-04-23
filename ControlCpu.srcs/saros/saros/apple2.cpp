#include <stdint.h>

#include <saros/sync/queue.h>

#include "8bit_hook.h"
#include "gpio.h"
#include "reg.h"
#include "uart.h"

#include <saros/saros.h>

namespace {
constexpr uint32_t ROMS_BASE = 0x8100'0000;
constexpr uint32_t BANK0_BASE = 0x8101'0000;

constexpr uint32_t PagerDeviceNum = 5;

constexpr uint32_t Pager_IoOp = 128;

uint32_t pendingKeyboardChar;

void uartHandler(void *) noexcept {
    while(true) {
        uint32_t ch = uart_recv_char();

        if( (ch & UART_RX_SPECIAL_MASK)!=0 ) {
        } else {
            pendingKeyboardChar = ch | 0x80;
        }
    }
}

Saros::Sync::Queue<uint32_t, 16> ioQueue;

static constexpr uint32_t IO_ADDR_MASK  = 0x0000ffff, IO_ADDR_SHIFT = 0;
static constexpr uint32_t IO_DATA_MASK  = 0x00ff0000, IO_DATA_SHIFT = 16;
static constexpr uint32_t IO_WRITE_MASK = 0x40000000, IO_WRITE_SHIFT = 30;
static constexpr uint32_t IO_VALID_MASK = 0x80000000, IO_VALID_SHIFT = 31;

void appleIoHandler(void *) noexcept {
    uint32_t result = 0;

    while(true) {
        uint32_t event = ioQueue.pop();

        uint16_t addr = (event & IO_ADDR_MASK) >> IO_ADDR_SHIFT;
        if( (addr & 0xff00) == 0xc000 ) {
            // IO region
            switch( addr & IO_ADDR_MASK ) {
            case 0xc000:
            case 0xc001:
            case 0xc002:
            case 0xc003:
            case 0xc004:
            case 0xc005:
            case 0xc006:
            case 0xc007:
            case 0xc008:
            case 0xc009:
            case 0xc00a:
            case 0xc00b:
            case 0xc00c:
            case 0xc00d:
            case 0xc00e:
            case 0xc00f:
                result = pendingKeyboardChar;
                break;
            case 0xc010:
            case 0xc011:
            case 0xc012:
            case 0xc013:
            case 0xc014:
            case 0xc015:
            case 0xc016:
            case 0xc017:
            case 0xc018:
            case 0xc019:
            case 0xc01a:
            case 0xc01b:
            case 0xc01c:
            case 0xc01d:
            case 0xc01e:
            case 0xc01f:
                result = pendingKeyboardChar;
                pendingKeyboardChar &= 0x7f;
                break;
            }
        } else {
            // ROM region
            result = 0xff;
        }

        reg_write_32( PagerDeviceNum, Pager_IoOp, result );
        saros.enableSoftwareInterrupt();
    }
}

}

void start_8bit() {
    uart_send("Initialize Apple II memory banks\n");

    // Main memory bank points to BANK0
    reg_write_32( PagerDeviceNum, 0, BANK0_BASE );      // Main section read
    reg_write_32( PagerDeviceNum, 12, BANK0_BASE );     // Main section write

    reg_write_32( PagerDeviceNum, 4, ROMS_BASE );       // Page D000 read
    reg_write_32( PagerDeviceNum, 16, BANK0_BASE );     // Page D000 write
    reg_write_32( PagerDeviceNum, 8, ROMS_BASE );       // Page E000 and F000 read
    reg_write_32( PagerDeviceNum, 20, BANK0_BASE );     // Page E000 and F000 write

    saros.createThread( uartHandler, nullptr );
    saros.createThread( appleIoHandler, nullptr, true );

    saros.enableSoftwareInterrupt();

    // Take 6502, the clock divider and display out of reset
    uart_send("Start the Apple II\n");
    write_gpio(0, 0xfffffff8);
}

void handleSoftwareInterrupt() {
    uint32_t ioOp = reg_read_32( PagerDeviceNum, Pager_IoOp );

    ioQueue.pushIrq( ioOp );
    saros.disableSoftwareInterrupt();
}
