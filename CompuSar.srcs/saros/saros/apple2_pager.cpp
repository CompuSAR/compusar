#include "apple2_pager.hh"

#include <abort.h>
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

namespace {
    uint32_t mapper[PagerBanks::DevNull + 1][2] = {};
    uint32_t slotRoms[8];
};

void setPageMapping(PagerBanks bank, bool write, uint8_t *address) {
    assertWithMessage( bank < (sizeof(mapper) / sizeof(mapper[0])), "setPageMapping bank must be an enum value" );
    auto addrInt = reinterpret_cast<uint32_t>(address);
    reg_write_32(
            DeviceNum,
            static_cast<uint32_t>(bank)*4 + (write ? Pager_WriteOffset : 0),
            addrInt );

    mapper[bank][write ? 1 : 0] = addrInt;
}

void setSlotMapping(uint8_t slot, const uint8_t *address) {
    assertWithMessage(slot < 8, "setSlotMapping slot must be in the range [0,8)");
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
    slotRoms[slot] = addrValue;
}

uint8_t *translateAddr(uint16_t address, bool write) {
    // The logic here must be synchronized with the logic at apple_pager.sv
    uint32_t addrMask;

    switch( address>>12 ) {
    case 0x0:
    case 0x1:
    case 0x2:
    case 0x3:
    case 0x4:
    case 0x5:
    case 0x6:
    case 0x7:
    case 0x8:
    case 0x9:
    case 0xa:
    case 0xb:
        addrMask = mapper[PagerBanks::Main][write ? 1 : 0];
        break;
    case 0xc:
        {
            uint8_t slot = (address>>8) &0x0f;

            if( slot==0 )
                addrMask = mapper[PagerBanks::Io][0];
            else if( slot>=8 )
                addrMask = slotRoms[0];
            else
                addrMask = slotRoms[slot];
        }
        break;
    case 0xd:
        addrMask = mapper[PagerBanks::D][write ? 1 : 0];
        break;
    case 0xe:
    case 0xf:
        addrMask = mapper[PagerBanks::EF][write ? 1 : 0];
        break;
    }

    if( addrMask==0 ) {
        return reinterpret_cast<uint8_t *>( mapper[PagerBanks::DevNull][write ? 1 : 0] );
    }

    addrMask ^= address;

    return reinterpret_cast<uint8_t *>(addrMask);
}

} // namespace Apple2
