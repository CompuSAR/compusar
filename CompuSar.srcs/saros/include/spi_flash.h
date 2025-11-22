#pragma once

#include <cstdint>
#include <cstddef>

namespace SPI_FLASH {

void init();
void deinit();
void initiate_read(uint32_t start_address, size_t size, void *dest);

struct FlashId {
    uint8_t manufacturer_id;
    uint8_t memory_type; // 0xba = 3V, 0xbb = 1v8
    uint8_t memory_capacity; // 0x22=2Gb, 0x21=1Gb, 0x20=512Mb, 0x19=256Mb, 0x18=128Mb, 0x17=64Mb
    uint8_t id_length;
    uint8_t extended_id;
    uint8_t unique_id[14];
    uint8_t padding[12];
};

FlashId readId();

void wait_done();

} // namespace SPI_FLASH
