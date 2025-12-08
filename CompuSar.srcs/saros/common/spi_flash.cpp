#include "spi_flash.h"

#include "spi.h"
#include "uart.h"
#include "format.h"

namespace SPI_FLASH {

enum class Commands : uint8_t {
    // Software reset operations
    ResetEnable                                 = 0x66,
    ResetMemory                                 = 0x99,

    // Read ID operations
    ReadId                                      = 0x9e,
    ReadId2                                     = 0x9f,
    MultiplIOReadId                             = 0xaf,
    ReadSerialFlashDiscoveryParameters          = 0x5a,

    // Read memory operations
    Read                                        = 0x03,
    FastRead                                    = 0x0b,
    DualOutputFastRead                          = 0x3b,
    DualIOFastRead                              = 0xbb,
    QuadOutputFastRead                          = 0x6b,
    QuadIOFastRead                              = 0xeb,
    DtrFastRead                                 = 0x0d,
    DtrDualOutputFastRead                       = 0x3d,
    DtrDualIOFastRead                           = 0xbd,
    DtrQuadOutputFastRead                       = 0x6d,
    DtrQuadIOFastRead                           = 0xed,
    QuadIOWordRead                              = 0xe7,

    // Write operations
    WriteEnable                                 = 0x06,
    WriteDisable                                = 0x04,

    // Read register operations
    ReadStatusRegister                          = 0x05,
    ReadFlagStatusRegister                      = 0x70,
    ReadNVConfRegister                          = 0xb5,
    ReadVolatileConfRegister                    = 0x85,
    ReadEnhancedVolatileConfRegister            = 0x65,
    ReadGeneralPurposeReadRegister              = 0x96,

    // Write register operations
    WriteStatusRegister                         = 0x01,
    WriteNVconfRegister                         = 0xb1,
    WriteVolatileConfRegister                   = 0x81,
    WriteEnhancedVolatileConfRegister           = 0x61,

    // Clear flag status register
    ClearFlagStatusRegister                     = 0x50,

    // Program operations
    PageProgram                                 = 0x02,
    DualInputFastProgram                        = 0xa2,
    ExtendedDualInputFastProgram                = 0xd2,
    QuadInputFastProgram                        = 0x32,
    ExtendedQuadInputFastProgram                = 0x38,

    // Erase operations
    SubsectorErase32K                           = 0x52,
    SubsectorErase4K                            = 0x20,
    SectorErase64K                              = 0xd8,
    BulkErase                                   = 0xc7,
    BulkErase2                                  = 0x60,

    // Quad protocol operations
    EnterQuadIOMode                             = 0x35,
    ResetQuadIOMode                             = 0xf5,

    // Advanced function interface operations
    InterfaceActivation                         = 0x9b,
    CyclicRedundancyCheck                       = 0x9b,
    CyclicRedundancyCheck2                      = 0x27,
};

struct SpiCommand {
    Commands cmd;
    uint8_t bytes[15];
} __attribute__(( aligned(16) ));

template<size_t NumWords>
struct SpiResult {
    uint8_t bytes[16*NumWords];
} __attribute__(( aligned(16) ));

static size_t last_op_size = 0;
static void *last_op_dest = nullptr;
static constexpr size_t NumDummyCycles = 3;

FlashId read_id() {
    SpiCommand cmd;
    FlashId id __attribute__(( aligned(16) ));

    cmd.cmd = Commands::MultiplIOReadId;

    SPI::start_transaction( &cmd, 1, 0, &id, sizeof(id) );
    SPI::wait_transaction();
    SPI::postprocess_buffer( &id, sizeof(id) );

    return id;
}

static void write_enable() {
    SpiCommand cmd;

    cmd.cmd = Commands::WriteEnable;
    SPI::start_transaction( &cmd, 1, 0, nullptr, 0 );
    SPI::wait_transaction();
}

void init() {
    SpiCommand cmd;
    
    // Make sure the flash is in a known state
    SPI::interface_rescue();

    FlashId id = read_id();
    uart_send("Flash Id (Single): ");
    unsigned len = id.id_length;
    len += 4;
    if( len>40 )
        len = 40;
    for( unsigned i=0; i<len; ++i ) {
        uart_send(" ");
        print_hex(reinterpret_cast<const uint8_t *>(&id)[i]);
    }
    uart_send("\n");

    // Allow writes to the NV reg
    set_config( SPI::Config::Single );
    write_enable();

    // Set dummy cycles
    cmd.cmd = Commands::WriteVolatileConfRegister;
    cmd.bytes[0] = (NumDummyCycles<<4) | 0x0b; // No XIP, continuous wrap
    SPI::start_transaction( &cmd, 2, 0, nullptr, 0 );
    SPI::wait_transaction();

    write_enable();

    // Set flash state to Quad SPI
    cmd.cmd = Commands::WriteEnhancedVolatileConfRegister;
    cmd.bytes[0] = 0x2f; // Quad I/O, single rate, Hold disabled, default driver strength
    SPI::start_transaction( &cmd, 2, 0, nullptr, 0 );
    SPI::wait_transaction();

    set_config( SPI::Config::Quad );

    id = read_id();
    len = id.id_length;
    len += 4;
    if( len>40 )
        len = 40;
    uart_send("Flash Id (Quad):   ");
    for( int i=0; i<len; ++i ) {
        uart_send(" ");
        print_hex(reinterpret_cast<const uint8_t *>(&id)[i]);
    }
    uart_send("\n");
}

void deinit() {
    SpiCommand cmd;

    SPI_FLASH::write_enable();
    cmd.cmd = Commands::WriteVolatileConfRegister;
    cmd.bytes[0] = 0xfb;
    SPI::start_transaction( &cmd, 2, 0, nullptr, 0 );
    SPI::wait_transaction();

    write_enable();

    cmd.cmd = Commands::WriteEnhancedVolatileConfRegister;
    cmd.bytes[0] = 0xff; // Quad I/O, single rate, Hold disabled, default driver strength
    SPI::start_transaction( &cmd, 2, 0, nullptr, 0 );
    SPI::wait_transaction();

    set_config( SPI::Config::Quad );
}

void erase_all() {
    SpiCommand cmd;
    uint8_t result[16] __attribute__(( aligned(16) ));

    write_enable();

    cmd.cmd = Commands::BulkErase;
    SPI::start_transaction( &cmd, 1, 0, nullptr, 0 );
    SPI::wait_transaction();
    uart_send("Erase started\n");

    do {
        cmd.cmd = Commands::ReadStatusRegister;
        SPI::start_transaction( &cmd, 1, 0, &result[0], 1 );
        SPI::wait_transaction();
    } while(result[0] & 1);

    print_hex(result[0]);
    uart_send("\n");
}

void initiate_read(uint32_t start_address, size_t size, void *dest) {
    SpiCommand cmd;

    cmd.cmd = Commands::FastRead;
    cmd.bytes[0] = (start_address>>16) & 0xff;
    cmd.bytes[1] = (start_address>>8) & 0xff;
    cmd.bytes[2] = start_address & 0xff;

    SPI::start_transaction( &cmd, 4, NumDummyCycles, dest, size );
    last_op_dest = dest;
    last_op_size = size;
}

void wait_done() {
    SPI::wait_transaction();

    if( last_op_size!=0 )
        SPI::postprocess_buffer( last_op_dest, last_op_size );

    last_op_dest = nullptr;
    last_op_size = 0;
}

} // namespace SPI_FLASH
