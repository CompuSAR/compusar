#pragma once

#include <cstdint>

#include <array>

namespace Apple2::Display {

struct CharBitmap {
    union {
        uint32_t raw[2];
        uint8_t  bits[8];
    };
};

enum class DisplayPage {
    Page1,
    Page2,
};

using CharSet = std::array< CharBitmap, 128 >;

namespace {
    extern "C" const CharSet charset_us;
}

void initDisplay(const CharSet &charset);

void loadCharset(const CharSet &charset);

void textMode(DisplayPage page, bool mode_80col);

} // namespace Apple2::Display
