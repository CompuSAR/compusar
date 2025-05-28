#include <stdint.h>
#include <string.h>

#include <saros/sync/queue.h>

#include "8bit_hook.h"
#include "gpio.h"
#include "reg.h"
#include "uart.h"

#include <saros/saros.h>

namespace {
constexpr uint32_t ROMS_BASE = 0x8100'0000;
constexpr uint32_t BANK0_BASE = 0x8101'0000;

constexpr size_t IO_BASE = 0xc000;

constexpr uint32_t PagerDeviceNum = 5;

constexpr uint32_t Pager_MainBank = 0x0000;
constexpr uint32_t Pager_IoBank = 0x0004;
constexpr uint32_t Pager_BankD = 0x0008;
constexpr uint32_t Pager_BanksEF = 0x000c;
constexpr uint32_t Pager_WriteOffset = 0x0800;
constexpr uint32_t Pager_IoOp = 0x1000;

static void io8_write(uint8_t port, uint8_t val) {
    reinterpret_cast<volatile uint8_t *>(ROMS_BASE)[IO_BASE + port] = val;
}

void uartHandler(void *) noexcept {
    while(true) {
        uint32_t ch = uart_recv_char();

        if( (ch & UART_RX_SPECIAL_MASK)!=0 ) {
        } else {
            //pendingKeyboardChar = ch | 0x80;
            uart_send(ch);

            for( uint8_t i=0x00; i<0x10; ++i ) {
                io8_write(i, ch|0x80);
            }

            for( uint8_t i=0x10; i<0x20; ++i ) {
                io8_write(i, ch);
            }
        }
    }
}

static constexpr uint32_t IO_ADDR_MASK  = 0x0000ffff, IO_ADDR_SHIFT = 0;
static constexpr uint32_t IO_DATA_MASK  = 0x00ff0000, IO_DATA_SHIFT = 16;
static constexpr uint32_t IO_WRITE_MASK = 0x40000000, IO_WRITE_SHIFT = 30;
static constexpr uint32_t IO_VALID_MASK = 0x80000000, IO_VALID_SHIFT = 31;

} // empty namespace

void start_8bit() {
    uart_send("Initialize Apple II memory banks\n");

    // Main memory bank points to BANK0
    reg_write_32( PagerDeviceNum, Pager_MainBank, BANK0_BASE );
    reg_write_32( PagerDeviceNum, Pager_MainBank | Pager_WriteOffset, BANK0_BASE );

    reg_write_32( PagerDeviceNum, Pager_BankD, ROMS_BASE );       // Page D000 read
    reg_write_32( PagerDeviceNum, Pager_BankD | Pager_WriteOffset, BANK0_BASE );     // Page D000 write
    reg_write_32( PagerDeviceNum, Pager_BanksEF, ROMS_BASE );       // Page E000 and F000 read
    reg_write_32( PagerDeviceNum, Pager_BanksEF | Pager_WriteOffset, BANK0_BASE );     // Page E000 and F000 write

    reg_write_32( PagerDeviceNum, Pager_IoBank, ROMS_BASE );
    reg_write_32( PagerDeviceNum, Pager_IoBank | Pager_WriteOffset, 0 );

    constexpr size_t IO_SLOTS_ROM_BASE = 0xc100;
    constexpr size_t IO_SHARED_ROM_BASE = 0xc800;
    memset(reinterpret_cast<void *>(ROMS_BASE + IO_SLOTS_ROM_BASE), 0xff, 256*7 + 256*8);
    memset(reinterpret_cast<void *>(ROMS_BASE + IO_BASE), 0x00, 256);

    saros.createThread( uartHandler, nullptr );

    saros.enableSoftwareInterrupt();

    // Take 6502, the clock divider and display out of reset
    uart_send("Start the Apple II\n");
    write_gpio(0, 0xfffffff8);
}

void handleSoftwareInterrupt() {
    return;
#if 0
    uint32_t ioOp = reg_read_32( PagerDeviceNum, Pager_IoOp );

    uint16_t addr = (ioOp & IO_ADDR_MASK) >> IO_ADDR_SHIFT;

    uint32_t result = 0;
    if( (addr & 0xff00) != 0 )
        result = 0xff;
    else {
        switch( addr & 0xff ) {
        case 0x00:
            result = pendingKeyboardChar;
            break;
        case 0x10:
            pendingKeyboardChar &= 0x7f;
            result = pendingKeyboardChar;
            break;
        }
    }

    reg_write_32( PagerDeviceNum, Pager_IoOp, result );
#endif
}
