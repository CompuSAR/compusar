#include <apple2_display.h>

#include <apple2.h>
#include <display.h>
#include <gpio.h>
#include <reg.h>

using Display::DeviceId;

namespace Apple2::Display {

static constexpr uint32_t Reg__BaseAddr1 =                      0x8000;
static constexpr uint32_t Reg__BaseAddrSplit1 =                 0x8004;
static constexpr uint32_t Reg__BaseAddr2 =                      0x8008;
static constexpr uint32_t Reg__BaseAddrSplit2 =                 0x800c;
static constexpr uint32_t Reg__DisplayYX =                      0x8010;
static constexpr uint32_t Reg__DisplayMode =                    0x8014;

static constexpr uint32_t Reg__CharRomBase =                    0xf000;

static constexpr uint32_t DisplayMode__Text =                   0x00000001;     // 1 means text, 0 means pixels
static constexpr uint32_t DisplayMode__HiRes =                  0x00000002;     // 1 means high, 0 means low
static constexpr uint32_t DisplayMode__DoubleRes =              0x00000004;     // 0 Means 40col/standard, 1 means 80/double
// Least significant byte stands for top 20 rows of the display, second byte for bottom 4
// Leave room for Video 7 RGB card special modes

static constexpr uint16_t BaseAddr_Text1 = 0x0400;
static constexpr uint16_t BaseAddr_Text2 = 0x0800;
static constexpr uint16_t BaseAddr_Hgr1 = 0x2000;
static constexpr uint16_t BaseAddr_Hgr2 = 0x4000;

void initDisplay(const CharSet *charset) {
    static constexpr uint32_t DISPLAY_RES_X = 640;
    static constexpr uint32_t DISPLAY_RES_Y = 480;
    static constexpr uint32_t APPLE_RES_X = 40 * 7 * 2; // 40 chars, 7 pixels per char, double pixels = 560
    static constexpr uint32_t APPLE_RES_Y = 24 * 8 * 2; // 24 rows, 8 pixels per row, we double the pixels = 384

    static constexpr uint32_t FramePositionY = (DISPLAY_RES_Y - APPLE_RES_Y)/2;
    static constexpr uint32_t FramePositionX = (DISPLAY_RES_X - APPLE_RES_X)/2;

    reg_write_32( DeviceId, Reg__DisplayYX, FramePositionY<<16 | FramePositionX );

    textMode(DisplayPage::Page1, false);

    loadCharset(charset);

    reset_gpio_bits(0, GPIO0__DISPLAY8_RESET);
}

void loadCharset(const CharSet *charset) {
    uint32_t offset = Reg__CharRomBase;

    for(auto &charDef : *charset) {
        reg_write_32( DeviceId, offset, charDef.raw[0] );
        offset += sizeof(uint32_t);
        reg_write_32( DeviceId, offset, charDef.raw[1] );
        offset += sizeof(uint32_t);
    }
}

void textMode(DisplayPage page, bool mode_80col) {
    switch( page ) {
    case DisplayPage::Page1:
        reg_write_32( DeviceId, Reg__BaseAddr1, BANK0_BASE + BaseAddr_Text1);
        reg_write_32( DeviceId, Reg__BaseAddrSplit1, BANK0_BASE + BaseAddr_Text1);
        reg_write_32( DeviceId, Reg__BaseAddr2, BANK1_BASE + BaseAddr_Text1);
        reg_write_32( DeviceId, Reg__BaseAddrSplit2, BANK1_BASE + BaseAddr_Text1);
        break;
    case DisplayPage::Page2:
        reg_write_32( DeviceId, Reg__BaseAddr1, BaseAddr_Text2);
        reg_write_32( DeviceId, Reg__BaseAddrSplit1, BaseAddr_Text2);
        reg_write_32( DeviceId, Reg__BaseAddr2, BANK1_BASE + BaseAddr_Text2);
        reg_write_32( DeviceId, Reg__BaseAddrSplit2, BANK1_BASE + BaseAddr_Text2);
        break;
    }

    uint32_t mode = DisplayMode__Text;
    if( mode_80col )
        mode |= DisplayMode__DoubleRes;

    reg_write_32( DeviceId, Reg__DisplayMode, mode | (mode<<8) );
}

} // namespace Apple2::Display
