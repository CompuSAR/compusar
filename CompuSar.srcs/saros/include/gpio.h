#pragma once

#include <stdint.h>
#include <stddef.h>

uint32_t read_gpio(size_t gpio_num);
void write_gpio(size_t gpio_num, uint32_t value);
void set_gpio_bits(size_t gpio_num, uint32_t mask);
void reset_gpio_bits(size_t gpio_num, uint32_t mask);

static constexpr size_t GPIO0__DDR_RESET        = 0x00000001;
static constexpr size_t GPIO0__DISPLAY32_RESET  = 0x00000002;
