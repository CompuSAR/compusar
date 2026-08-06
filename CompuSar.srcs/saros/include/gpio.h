#pragma once

#include <stdint.h>
#include <stddef.h>

uint32_t read_gpio(size_t gpio_num);
void write_gpio(size_t gpio_num, uint32_t value);
void set_gpio_bits(size_t gpio_num, uint32_t mask);
void reset_gpio_bits(size_t gpio_num, uint32_t mask);

static constexpr size_t GPO0__DDR_RESET         = 0x00000001;
static constexpr size_t GPO0__DISPLAY32_RESET   = 0x00000002;
static constexpr size_t GPO0__DISPLAY8_RESET    = 0x00000004;
static constexpr size_t GPO0__SD_CARD_POLARITY  = 0x00000008;

static constexpr size_t GPI0__SWITCHES          = 0x0000000f;
static constexpr size_t GPI0__SD_CARD_IN_N      = 0x00000010;
static constexpr size_t GPI0__SD_CARD_DATA_IDLE = 0x00000020;

// Apple II GPIOs
static constexpr size_t GPO0__6502_RESET        = 0x00010000;
static constexpr size_t GPO0__FREQ_DIV_RESET    = 0x00020000;
static constexpr size_t GPO0__A2_DISK_CTRL_RESET= 0x00040000;
