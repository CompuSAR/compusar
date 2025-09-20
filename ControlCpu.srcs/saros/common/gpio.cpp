#include <gpio.h>

#include <reg.h>

static constexpr uint32_t DeviceNum = 2;

static volatile uint32_t *gpio_base = reinterpret_cast<uint32_t *>(0xc002'0000);

uint32_t read_gpio(size_t gpio_num) {
    return reg_read_32( DeviceNum, gpio_num );
}

void write_gpio(size_t gpio_num, uint32_t value) {
    reg_write_32( DeviceNum, gpio_num, value );
}
