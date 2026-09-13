#include "apple2_pager.hh"

#include <reg.h>

constexpr uint32_t DeviceNum = 0x80;

constexpr uint32_t Pager_MainBank = 0x0000;
constexpr uint32_t Pager_IoBank = 0x0004;
constexpr uint32_t Pager_BankD = 0x0008;
constexpr uint32_t Pager_BanksEF = 0x000c;
constexpr uint32_t Pager_DevNull = 0x0010;
constexpr uint32_t Pager_SlotRomsOffset = 0x0100;
constexpr uint32_t Pager_WriteOffset = 0x0800;
constexpr uint32_t Pager_IoOp = 0x1000;

namespace Apple2 {

void setPageMapping(PagerBanks bank, bool write, uint8_t *address) {
    reg_write_32(
            DeviceNum,
            static_cast<uint32_t>(bank)*4 + (write ? Pager_WriteOffset : 0),
            reinterpret_cast<uint32_t>(address) );
}

void setSlotMapping(uint8_t slot, const uint8_t *address) {
    uint32_t addrValue = 0;

    if( address!=nullptr ) {
        // The decoder will XOR its address with the address we give. In order to have it point to `address`, we need to xor
        // now with the address of the slot ROM base.
        addrValue = reinterpret_cast<uint32_t>(address);
        addrValue ^= 0xc000 + slot * 0x0100;
    }

    reg_write_32(
            DeviceNum,
            Pager_SlotRomsOffset + slot*16,
            addrValue );
}

uint8_t *translateAddr(uint16_t address);

} // namespace Apple2
