#include "display.h"

namespace Display {

namespace {
static constexpr uint32_t DeviceId = 5;

static constexpr uint32_t Reg__BaseAddr = 0;
static constexpr uint32_t Reg__FrameHeightWidth = 4;
static constexpr uint32_t Reg__FrameStart = 8;
}

void setDisplay(const Bitmap &bitmap) {
}

} // namespace Display
