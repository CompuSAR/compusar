#pragma once

#include <stdint.h>

uint32_t reg_read_32(uint32_t device, uint32_t reg);
uint64_t reg_read_64(uint32_t device, uint32_t reg);
void reg_write_32(uint32_t device, uint32_t reg, uint32_t value);
void reg_write_64(uint32_t device, uint32_t reg, uint64_t value);
