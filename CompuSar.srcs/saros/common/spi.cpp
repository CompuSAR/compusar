#include "spi.h"

#include "hw-params.h"
#include "memory.h"
#include "reg.h"

#include <cstddef>

namespace SPI {

static constexpr uint32_t SpiDevice = 4;

enum SpiRegister : uint32_t {
    REG_TRIGGER                 = 0x0000,
    REG_SEND_DMA_ADDR           = 0x0004,
    REG_NUM_SEND_CYCLES         = 0x0008,
    REG_RECV_DMA_ADDR           = 0x000c,
    REG_NUM_RECV_CYCLES         = 0x0010,
    REG_MODE                    = 0x0014,
};

static Config current_config = Config(0xff);

void set_config( Config config ) {
    current_config = config;
}

void postprocess_buffer( void *buffer, size_t recv_size ) {
    // Realign the response to the beginning of the cacheline
    if( recv_size%CACHELINE_SIZE_BYTES!=0 ) {
        std::byte *buffer_c = reinterpret_cast<std::byte *>(buffer);
        buffer_c += (recv_size/CACHELINE_SIZE_BYTES) * CACHELINE_SIZE_BYTES;     // Only the last line needs special handling

        const size_t delta = CACHELINE_SIZE_BYTES - recv_size%CACHELINE_SIZE_BYTES;
        for( int i=(recv_size%CACHELINE_SIZE_BYTES)-1; i>=0; --i ) {
            buffer_c[i] = buffer_c[i+delta];
        }
    }
}

void start_transaction( const void *send_buffer, size_t send_size, uint16_t num_dummy_cycles, void *recv_buffer, size_t recv_size )
{
    // First write the values that the SPI clocked parts need
    reg_write_32( SpiDevice, REG_MODE, static_cast<uint32_t>(num_dummy_cycles) | (static_cast<uint32_t>(current_config)<<16) );
    if( current_config==Config::Single ) {
        reg_write_32( SpiDevice, REG_NUM_SEND_CYCLES, send_size*8 );
        reg_write_32( SpiDevice, REG_NUM_RECV_CYCLES, recv_size*8 );
    } else {
        reg_write_32( SpiDevice, REG_NUM_SEND_CYCLES, send_size*2 );
        reg_write_32( SpiDevice, REG_NUM_RECV_CYCLES, recv_size*2 );
    }
    // Then write the values it doesn't, so the first have time to propagate
    reg_write_32( SpiDevice, REG_SEND_DMA_ADDR, reinterpret_cast<uint32_t>(send_buffer) );
    reg_write_32( SpiDevice, REG_RECV_DMA_ADDR, reinterpret_cast<uint32_t>(recv_buffer) );

    wwb();

    reg_write_32( SpiDevice, REG_TRIGGER, 0 );
}

void wait_transaction() {
    reg_read_32( SpiDevice, REG_TRIGGER );
}

struct RecoveryData {
    uint8_t data[5] = {
        0xff, 0xff, 0xff, 0xff, 0x01
    };
} __attribute__((aligned(16) ))__;
const RecoveryData RecoveryFirstStepData;
static void recovery_helper(uint32_t num_cycles) {
    set_config( Config::Single );
    reg_write_32( SpiDevice, REG_MODE, 0 ); // Single SPI, no dummy cycles
    reg_write_32( SpiDevice, REG_NUM_SEND_CYCLES, num_cycles );
    reg_write_32( SpiDevice, REG_NUM_RECV_CYCLES, 0 );
    reg_write_32( SpiDevice, REG_SEND_DMA_ADDR, reinterpret_cast<uint32_t>(&RecoveryFirstStepData.data) );
    reg_write_32( SpiDevice, REG_RECV_DMA_ADDR, 0 );
    reg_write_32( SpiDevice, REG_TRIGGER, 0 );
}

static void recovery_first_step() {
    recovery_helper(7);
    recovery_helper(9);
    recovery_helper(13);
    recovery_helper(17);
    recovery_helper(25);
    recovery_helper(33);
}

void interface_rescue() {
    recovery_first_step();
    recovery_helper(16);
}

} // namespace SPI
