#include "display.h"

#include "reg.h"

namespace Display {

namespace {
static constexpr uint32_t DeviceId = 5;

static constexpr uint32_t Reg__BaseAddr = 0;
static constexpr uint32_t Reg__FrameHeightWidth = 4;
static constexpr uint32_t Reg__FrameStart = 8;
}

void setDisplay(const Bitmap &bitmap, uint16_t originX, uint16_t originY) {
    reg_write_32(DeviceId, Reg__BaseAddr, reinterpret_cast<uint32_t>(&bitmap.data[0]));
    reg_write_32(DeviceId, Reg__FrameHeightWidth, bitmap.height<<16 | bitmap.width);
    reg_write_32(DeviceId, Reg__FrameStart, originY<<16 | originX);
}


} // namespace Display
