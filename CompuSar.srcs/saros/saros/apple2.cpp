#include <apple2.h>

#include <apple2_display.h>

#include "8bit_hook.h"
#include "gpio.h"
#include "reg.h"
#include "uart.h"

#include <saros/saros.h>

#include <string.h>

using namespace Apple2;

namespace {

constexpr size_t IO_BASE = 0xc000;

constexpr size_t IO_KBD         = IO_BASE + 0x00;
constexpr size_t IO_KBDSTRB     = IO_BASE + 0x10;
constexpr size_t IO_TAPEOUT     = IO_BASE + 0x20;
constexpr size_t IO_SPKR        = IO_BASE + 0x30;
constexpr size_t IO_TXTCLR      = IO_BASE + 0x50;
constexpr size_t IO_TXTSET      = IO_BASE + 0x51;
constexpr size_t IO_MIXSET      = IO_BASE + 0x53;
constexpr size_t IO_TXTPAGE1    = IO_BASE + 0x54;
constexpr size_t IO_LORES       = IO_BASE + 0x56;
constexpr size_t IO_SETAN0      = IO_BASE + 0x58;
constexpr size_t IO_SETAN1      = IO_BASE + 0x5a;
constexpr size_t IO_CLRAN2      = IO_BASE + 0x5d;
constexpr size_t IO_CLRAN3      = IO_BASE + 0x5f;
constexpr size_t IO_TAPEIN      = IO_BASE + 0x60;
constexpr size_t IO_PADDL0      = IO_BASE + 0x64;
constexpr size_t IO_PTRIG       = IO_BASE + 0x70;

constexpr uint32_t PagerDeviceNum = 0x80;

constexpr uint32_t Pager_MainBank = 0x0000;
constexpr uint32_t Pager_IoBank = 0x0004;
constexpr uint32_t Pager_BankD = 0x0008;
constexpr uint32_t Pager_BanksEF = 0x000c;
constexpr uint32_t Pager_DevNull = 0x0010;
constexpr uint32_t Pager_SlotRomsOffset = 0x0100;
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
    uart_send("Keyboard handling thread started\n");
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

extern const uint8_t DISK2_fw[];

void start_8bit() {
    static uint8_t devNullDataWrite;                    // All writes that get ignored are routed here
    static const uint8_t devNullDataRead = 0xa5;        // All reads that get ignored are routed here
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

    reg_write_32( PagerDeviceNum, Pager_DevNull, reinterpret_cast<uint32_t>(&devNullDataRead) );
    reg_write_32( PagerDeviceNum, Pager_DevNull | Pager_WriteOffset, reinterpret_cast<uint32_t>(&devNullDataWrite) );

    for( unsigned i=1; i<=8; ++i ) {
        // Devnull all slot ROMs
        reg_write_32( PagerDeviceNum, Pager_SlotRomsOffset + i*16, 0 );
    }

    constexpr size_t IO_SLOTS_ROM_BASE = 0xc100;
    constexpr size_t IO_SHARED_ROM_BASE = 0xc800;
    memset(reinterpret_cast<void *>(ROMS_BASE + IO_SLOTS_ROM_BASE), 0xff, 256*7 + 256*8);
    memset(reinterpret_cast<void *>(ROMS_BASE + IO_BASE), 0x00, 256);

    Display::initDisplay(Display::charset_us);

    // Fill main memory with junk so it registers as a cold boot
    uart_send("Seed memory\n");
    for( auto ptr = reinterpret_cast<uint32_t *>(BANK0_BASE); ptr != reinterpret_cast<uint32_t *>(BANK0_BASE + 2048); ++ptr )
        *ptr = 0xff00ff00;

    saros.createThread( uartHandler, nullptr, "UART keyboard"_fs );

    saros.enableSoftwareInterrupt();

    // Take the 6502 and the clock divider out of reset
    uart_send("Start the Apple II\n");
    reset_gpio_bits(0, GPO0__6502_RESET | GPO0__FREQ_DIV_RESET);
}

union IoOp {
    uint32_t value;
    struct {
        uint32_t addr:16;
        uint32_t data:8;
        uint32_t padding:6;
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
