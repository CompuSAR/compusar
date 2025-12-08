#pragma once

#include <stdint.h>
#include <stddef.h>

uint32_t read_gpio(size_t gpio_num);
void write_gpio(size_t gpio_num, uint32_t value);
