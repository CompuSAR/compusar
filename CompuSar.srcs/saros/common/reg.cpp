#include "reg.h"

static constexpr uint32_t RegistersBase = 0xc000'0000;

static volatile uint32_t *registers_base(uint32_t device) {
    return reinterpret_cast<volatile uint32_t *>(RegistersBase | device<<16);
}

uint32_t reg_read_32(uint32_t device, uint32_t reg) {
    return registers_base(device)[reg / 4];
}

uint64_t reg_read_64(uint32_t device, uint32_t reg) {
    uint64_t ret = reg_read_32(device, reg);
    ret |= static_cast<uint64_t>( reg_read_32(device, reg+4) )<<32;

    return ret;
}

void reg_write_32(uint32_t device, uint32_t reg, uint32_t value) {
    registers_base(device)[reg / 4] = value;
}

void reg_write_64(uint32_t device, uint32_t reg, uint64_t value) {
    reg_write_32(device, reg, value&0xffffffff);
    reg_write_32(device, reg+4, value>>32);
}
