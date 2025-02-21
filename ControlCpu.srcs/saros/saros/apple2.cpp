#include <stdint.h>

#include "8bit_hook.h"
#include "gpio.h"
#include "reg.h"
#include "uart.h"

static constexpr uint32_t ROMS_BASE = 0x8100'0000;
static constexpr uint32_t BANK0_BASE = 0x8101'0000;

static constexpr uint32_t PagerDeviceNum = 5;

void start_8bit() {
    uart_send("Initialize Apple II memory banks\n");

    // Main memory bank points to BANK0
    reg_write_32( PagerDeviceNum, 0, BANK0_BASE );      // Main section read
    reg_write_32( PagerDeviceNum, 12, BANK0_BASE );     // Main section write

    reg_write_32( PagerDeviceNum, 4, ROMS_BASE );       // Page D000 read
    reg_write_32( PagerDeviceNum, 16, BANK0_BASE );     // Page D000 write
    reg_write_32( PagerDeviceNum, 8, ROMS_BASE );       // Page E000 and F000 read
    reg_write_32( PagerDeviceNum, 20, BANK0_BASE );     // Page E000 and F000 write

    // Take 6502, the clock divider and display out of reset
    uart_send("Start the Apple II\n");
    write_gpio(0, 0xfffffff8);
}
