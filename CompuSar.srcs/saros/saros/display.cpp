#include "display.h"

#include "reg.h"

namespace Display {

Saros::Sync::Signal vsyncSignal;

namespace {
static constexpr uint32_t Reg__BaseAddr =               0x0000;
static constexpr uint32_t Reg__FrameHeightWidth =       0x0004;
static constexpr uint32_t Reg__FrameStart =             0x0008;
static constexpr uint32_t Reg__AckIrq =                 0x000c;
}

void setDisplay(const Bitmap &bitmap, uint16_t originX, uint16_t originY) {
    reg_write_32(DeviceId, Reg__BaseAddr, reinterpret_cast<uint32_t>(&bitmap.data[0]));
    reg_write_32(DeviceId, Reg__FrameHeightWidth, bitmap.height<<16 | bitmap.width);
    reg_write_32(DeviceId, Reg__FrameStart, originY<<16 | originX);
}

void handle_vsync_irq() {
    vsyncSignal.signal();

    reg_write_32(DeviceId, Reg__AckIrq, 0);
}

} // namespace Display
