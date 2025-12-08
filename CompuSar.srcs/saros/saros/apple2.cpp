#include <stdint.h>
#include <string.h>

#include "8bit_hook.h"
#include "gpio.h"
#include "reg.h"
#include "uart.h"

#include <saros/saros.h>

namespace {
constexpr uint32_t ROMS_BASE = 0x8100'0000;
constexpr uint32_t BANK0_BASE = 0x8101'0000;

constexpr size_t IO_BASE = 0xc000;

constexpr size_t IO_KBD         = 0x00;
constexpr size_t IO_KBDSTRB     = 0x10;
constexpr size_t IO_TAPEOUT     = 0x20;
constexpr size_t IO_SPKR        = 0x30;
constexpr size_t IO_TXTCLR      = 0x50;
constexpr size_t IO_TXTSET      = 0x51;
constexpr size_t IO_MIXSET      = 0x53;
constexpr size_t IO_TXTPAGE1    = 0x54;
constexpr size_t IO_LORES       = 0x56;
constexpr size_t IO_SETAN0      = 0x58;
constexpr size_t IO_SETAN1      = 0x5a;
constexpr size_t IO_CLRAN2      = 0x5d;
constexpr size_t IO_CLRAN3      = 0x5f;
constexpr size_t IO_TAPEIN      = 0x60;
constexpr size_t IO_PADDL0      = 0x64;
constexpr size_t IO_PTRIG       = 0x70;

constexpr uint32_t PagerDeviceNum = 0x80;

constexpr uint32_t Pager_MainBank = 0x0000;
constexpr uint32_t Pager_IoBank = 0x0004;
constexpr uint32_t Pager_BankD = 0x0008;
constexpr uint32_t Pager_BanksEF = 0x000c;
constexpr uint32_t Pager_WriteOffset = 0x0800;
constexpr uint32_t Pager_IoOp = 0x1000;

constexpr uint32_t IoDeviceNum = 0x81;

constexpr uint32_t Io_Event = 0x0000;

static void io8_write(uint8_t port, uint8_t val) {
    reinterpret_cast<volatile uint8_t *>(ROMS_BASE)[IO_BASE + port] = val;
}

class KeyPress {
    uint8_t key = 0;

public:
    KeyPress() = default;

    void keyPressed(char ch) {
        key = ch | 0x80;

        updateMem();
    }

    uint8_t keyProbed() {
        key &= 0x7f;

        updateMem();

        return key;
    }

private:
    void updateMem() {
        for( uint8_t i=0x00; i<0x10; ++i ) {
            io8_write(i, key);
        }
    }
} lastKey;

void uartHandler(void *) noexcept {
    while(true) {
        uint32_t ch = uart_recv_char();

        if( (ch & UART_RX_SPECIAL_MASK)!=0 ) {
        } else {
            //pendingKeyboardChar = ch | 0x80;
            uart_send(ch);

            lastKey.keyPressed(ch);
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

    // Fill main memory with junk
    for( auto ptr = reinterpret_cast<uint32_t *>(BANK0_BASE); ptr != reinterpret_cast<uint32_t *>(BANK0_BASE + 64*1024); ++ptr )
        *ptr = 0xff00ff00;

    saros.createThread( uartHandler, nullptr );

    saros.enableSoftwareInterrupt();

    // Take 6502, the clock divider and display out of reset
    uart_send("Start the Apple II\n");
    reset_gpio_bits(0, GPIO0__6502_RESET | GPIO0__FREQ_DIV_RESET | GPIO0__DISPLAY8_RESET);
}

union IoOp {
    uint32_t value;
    struct {
        uint32_t addr:8;
        uint32_t data:8;
        uint32_t padding:13;
        uint32_t memReq:1;
        uint32_t write:1;
        uint32_t pending:1;
    };
};

void handleSoftwareInterrupt() {
    const IoOp ioOp{ .value = reg_read_32( IoDeviceNum, Io_Event ) };

    uint8_t result = 0;
    if( ioOp.write ) {
        switch( ioOp.addr ) {
        default:
            break;
        }
    } else {
        switch( ioOp.addr ) {
        case IO_KBDSTRB:
            result = lastKey.keyProbed();
            break;
        default:
            break;
        }
    }

    reg_write_32( IoDeviceNum, Io_Event, result );
}
