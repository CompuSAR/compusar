#pragma once

#include <stdint.h>
#include <stddef.h>

namespace SPI {

enum class Config {
    Single = 0,
    Quad,
};

void set_config( Config config );
void start_transaction( const void *send_buffer, size_t send_size, uint16_t num_dummy_cycles, void *recv_buffer, size_t recv_size );
void postprocess_buffer( void *buffer, size_t recv_size );
void wait_transaction();
void interface_rescue();

} // namespace SPI
