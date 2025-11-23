#pragma once

#include <cstdint>

namespace Display {

struct Bitmap {
    uint32_t width, height;
    alignas(16) uint8_t data[];
};

} // namespace Display
