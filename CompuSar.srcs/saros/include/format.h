#pragma once

#include <cstdint>
#include <span>

void print_hex(uint64_t number, bool sync = false);
void print_dec(uint64_t number);
void dump_memory(std::span<uint8_t> memory);
