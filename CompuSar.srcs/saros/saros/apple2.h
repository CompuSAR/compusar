#pragma once

#include <cstdint>

namespace Apple2 {

constexpr uint32_t ROMS_BASE = 0x8100'0000;
constexpr uint32_t BANK0_BASE = 0x8101'0000;
constexpr uint32_t BANK1_BASE = 0x8102'0000;

constexpr uint32_t IoDeviceNum = 0x81;
constexpr uint32_t Io_Event = 0x0000;

} // namespace Apple2
