#pragma once

#include <cstdint>

namespace Apple2 {

enum class PagerBanks {
    Main,       // Main bulk of memory
    Io,         // IO registers region (read only)
    D,          // Dxxx bank
    EF,         // Exxx and Fxxx banks
    DevNull,    // Unconnected read/writes
};

void setPageMapping(PagerBanks bank, bool write, uint8_t *address);
void setSlotMapping(uint8_t slot, const uint8_t *address);
uint8_t *translateAddr(uint16_t address);

} // namespace Apple2
