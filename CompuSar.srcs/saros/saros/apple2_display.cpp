#include <apple2_display.h>

#include <display.h>

using Display::DeviceId;

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
