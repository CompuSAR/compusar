#include "sd.h"

#include "saros/csr.h"
#include "saros/saros.h"

#include "format.h"
#include "gpio.h"
#include "irq.h"
#include "reg.h"
#include "uart.h"

#include <mutex>

/* In this file, any comment referencing a standard section refers to "SD Physical Layer Simplified Specification Ver 9.00"
 */

namespace {
// Write registers
constexpr uint32_t RegW__SetCmdArgument                 = 0x0000;
constexpr uint32_t RegW__SendCmd                        = 0x0004;
    constexpr uint32_t SetCmd__Reply48                  = 0x00000100;
    // The reply will have the CMD bits all set
    constexpr uint32_t SetCmd__ReplyCmd3f               = 0x00000400;
    constexpr uint32_t SetCmd__Reply136                 = 0x00000700;
    constexpr uint32_t SetCmd__ReadData                 = 0x00001000;
    constexpr uint32_t SetCmd__WriteData                = 0x00002000;
constexpr uint32_t RegW__DataDmaAddr                    = 0x0100;
constexpr uint32_t RegW__DataTransferParams             = 0x0104;
    constexpr uint32_t StartDataTransfer__SizeMask      = (1<<11) - 1;
    constexpr uint32_t StartDataTransfer__4Wire         = 0x80000000;

// Read registers
constexpr uint32_t RegR__GetStatus                      = 0x0000;
    constexpr uint32_t GetStatus__CmdBusy               = 0x80000000;
    constexpr uint32_t GetStatus__DataBusy              = 0x40000000;

    constexpr uint32_t GetStatus__Cmd_ReplyReceived     = 0x00000001;
    constexpr uint32_t GetStatus__Cmd_Timeout           = 0x00000010;
    constexpr uint32_t GetStatus__Cmd_Mismatch          = 0x00000020;
    constexpr uint32_t GetStatus__Cmd_CrcMismatch       = 0x00000040;
    constexpr uint32_t GetStatus__Cmd_InvalidReplyBit   = 0x00000080;
    constexpr uint32_t GetStatus__Cmd_ErrorMask         = 0x000000f0;

    constexpr uint32_t GetStatus__Data_Timeout          = 0x00010000;
    constexpr uint32_t GetStatus__Data_CrcMismatch      = 0x00020000;
    constexpr uint32_t GetStatus__Data_StopBitError     = 0x00040000;
    constexpr uint32_t GetStatus__Data_StartBitError    = 0x00080000;
    constexpr uint32_t GetStatus__Data_DataOverrun      = 0x00100000;
    constexpr uint32_t GetStatus__Data_ErrorMask        = 0x001f0000;

constexpr uint32_t RegR__GetReply0                      = 0x0010;
constexpr uint32_t RegR__GetReply1                      = 0x0014;
constexpr uint32_t RegR__GetReply2                      = 0x0018;
constexpr uint32_t RegR__GetReply3                      = 0x001c;

static constexpr uint32_t DeviceId = 6;
}

static constexpr uint8_t APP_CMD_BIT = 1<<7;
static constexpr uint8_t CMD_BITS_MASK = (1<<6) - 1;
enum class SdCmd : uint16_t {
    CMD0_GO_IDLE_STATE = 0,
    CMD2_ALL_SEND_CID = 2 | SetCmd__Reply136,
    CMD3_SEND_RELATIVE_ADDR = 3,
    CMD7_DE_SELECT_CARD = 7,
    CMD8_SEND_IF_COND = 8,
    CMD9_SEND_CSD = 9 | SetCmd__Reply136,
    CMD17_READ_SINGLE_BLOCK = 17 | SetCmd__ReadData,
    APP_CMD = 55,

    ACMD41_SD_SEND_OP_COND = 41 | APP_CMD_BIT | SetCmd__ReplyCmd3f,
};

union SdReply1 {
    uint32_t reply;
    struct {
        // Ordered LSB to MSB
        uint32_t reserved6 : 2;
        uint32_t reserved5 : 1;
        uint32_t akeSeqError : 1;
        uint32_t reserved4 : 1;
        uint32_t appCmd : 1;
        uint32_t fxEvent : 1;
        uint32_t reserved3 : 1;
        uint32_t readForData : 1;
        uint32_t currentState : 4;
        uint32_t eraseReset : 1;
        uint32_t cardEccDisabled : 1;
        uint32_t wpErasSkip : 1;
        uint32_t csdOverwrite : 1;
        uint32_t reserved2 : 1;
        uint32_t reserved1 : 1;
        uint32_t error : 1;
        uint32_t ccError : 1;
        uint32_t cardEccFailed : 1;
        uint32_t illegalCommand : 1;
        uint32_t comCrcError : 1;
        uint32_t lockUnlockFailed : 1;
        uint32_t cardIsLocked : 1;
        uint32_t wpViolation : 1;
        uint32_t eraseParamError : 1;
        uint32_t eraseSeqError : 1;
        uint32_t blockLengthError : 1;
        uint32_t addressError : 1;
        uint32_t outOfRangeError : 1;
    };
};
static_assert(sizeof(SdReply1) == sizeof(uint32_t));

struct uint128_t {
    uint32_t w0, w1, w2, w3;
};
static_assert(sizeof(uint128_t) == 16, "Wrong 128 bit type");

union CID {
    uint128_t raw;
    struct {
        uint32_t stopBit : 1;
        uint32_t crc : 7;
        uint32_t manufacturingMonth : 4;
        uint32_t manufacturingYear : 8;
        uint32_t reserved : 4;
        uint32_t prodSN2 : 8;
        uint32_t prodSN1 : 24;
        uint32_t prodRev : 8;
        char productName[5];
        uint32_t oid : 16;
        uint32_t manufacturerId : 8;
    };
};
static_assert(sizeof(CID) == 16);

union CSD {
    uint128_t raw;
    struct {
        uint32_t stopBit : 1;
        uint32_t crc : 7;
        uint32_t reserved1 : 1;
        uint32_t wpUpc : 1;             // Write protect until power cycle
        uint32_t fileFormat : 2;
        uint32_t tmpWriteProtect : 1;
        uint32_t permWriteProtect : 1;
        uint32_t copy : 1;
        uint32_t fileFormatGrp: 1;
        uint32_t reserved2 : 5;
        uint32_t writeBlPartial : 1;    // Legal to write partial blocks
        uint32_t writeBlLen : 4;        // Max write data block length
        uint32_t r2wFactor : 3;         // Write speed factor
        uint32_t reserved3 : 2;
        uint32_t wpGrpEnable : 1;
        uint32_t wpGrpSize : 7;
        uint32_t sectorSize : 7;
        uint32_t eraseBlkEn : 1;
        uint32_t cSizeMult : 3;
        uint32_t vddWCurrMax : 3;
        uint32_t vddWCurrMin : 3;
        uint32_t vddRCurrMax : 3;
        uint32_t vddRCurrMin : 3;
        uint32_t cSize_low : 2;
        uint32_t cSize_high : 10;
        uint32_t reserved4 : 2;
        uint32_t dsrImp : 1;
        uint32_t readBlkMisalign : 1;
        uint32_t writeBlkMisalign : 1;
        uint32_t readBlPartial : 1;
        uint32_t readBlLen : 4;
        uint32_t ccc : 12;              // Card command class
        uint32_t tranSpeed : 8;
        uint32_t nsac : 8;              // Data read access time 2 in CLK cycles
        uint32_t taac : 8;              // Data read access time 1
        uint32_t reserved5 : 6;
        uint32_t csdStructure : 2;
    } v1;
};
static_assert(sizeof(CSD) == 16);

namespace {
    SD sd;
};

static void send_sd_cmd(SdCmd command, uint32_t args);
[[nodiscard]] static uint32_t send_sd_cmd(SdCmd command, uint32_t args, uint32_t &reply);
[[nodiscard]] static uint32_t send_sd_cmd(SdCmd command, uint32_t args, uint128_t &reply);

SD::BlockPtr SD::readBlock(uint32_t blockNum) const {
    if( checkUninit() )
        return _blocksPool.emptyPtr();

    if( blockNum>=_numBlocks ) {
        uart_send("E: SD readBlock(");
        print_dec(blockNum);
        uart_send(" out of range\n");

        return _blocksPool.emptyPtr();
    }

    std::unique_lock dataLock(_dataLock);

    waitDataIdle();

    BlockPtr block = _blocksPool.alloc();

    reg_write_32(DeviceId, RegW__DataDmaAddr, reinterpret_cast<uint32_t>(block->data.data()));
    reg_write_32(DeviceId, RegW__DataTransferParams, BlockSize * 8);    // Size is in bits

    uint32_t addressMultiplier = 1;
    switch(_cardType) {
    case CardType::Sdsc:
        addressMultiplier = 8;
        break;
    default:
        addressMultiplier = 1;
    }

    SdReply1 reply;
    if( isError( send_sd_cmd(SdCmd::CMD17_READ_SINGLE_BLOCK, blockNum * addressMultiplier, reply.reply) ) )
        return _blocksPool.emptyPtr();
    // TODO check `reply` for errors

    waitDataIdle();
    uint32_t status = reg_read_32(DeviceId, RegR__GetStatus);
    print_hex(status);
    uart_send("\n");

    if( isDataError(reg_read_32(DeviceId, RegR__GetStatus)) )
        return _blocksPool.emptyPtr();

    return block;
}

[[nodiscard]] bool SD::isError(uint32_t status) {
    if( (status & GetStatus__Cmd_ErrorMask)==0 )
        return false;

    uart_send("E: SD error:");
    if( status & GetStatus__Cmd_Timeout )
        uart_send("  Timeout");
    if( status & GetStatus__Cmd_Mismatch )
        uart_send("  CMD mismatch");
    if( status & GetStatus__Cmd_CrcMismatch )
        uart_send("  CRC error");
    if( status & GetStatus__Cmd_InvalidReplyBit )
        uart_send("  Start/stop bit error");

    uart_send("\n");

    return true;
}

[[nodiscard]] bool SD::isDataError(uint32_t status) {
    if( (status & GetStatus__Data_ErrorMask)==0 )
        return false;

    uart_send("E: SD data error:");
    if( status & GetStatus__Data_Timeout )
        uart_send("  Timeout");
    if( status & GetStatus__Data_CrcMismatch )
        uart_send("  CRC error");
    if( status & GetStatus__Data_StopBitError )
        uart_send("  Stop bit");
    if( status & GetStatus__Data_StartBitError )
        uart_send("  Start bit");
    if( status & GetStatus__Data_DataOverrun )
        uart_send("  Data overrun");

    uart_send("\n");

    return true;
}

bool SD::isInserted() {
    return (read_gpio(0) & GPI0__SD_CARD_IN_N) == 0;
}

bool SD::checkUninit() const {
    // TODO implement generations to detect card removal and insertion

    return _cardType == CardType::Uninit;
}

void SD::waitDataIdle() const {
    using namespace Saros;

    while(true) {
        // Disable interrupts
        csr_read_clr_bits<CSR::mstatus>( MSTATUS__MIE );

        if( read_gpio(0) & GPI0__SD_CARD_DATA_IDLE ) {
            csr_read_set_bits<CSR::mstatus>( MSTATUS__MIE );
            return;
        }

        irq_external_unmask( IrqExt__SdCardDataIdle );
        _dataIdle.wait();
    }
}

void SD::initCard() {
    // Implement the init state machine described in section 4.2.3

    CardType cardType = CardType::Uninit;

    // Reset the SD to power-on state, regardless of pervious state
    uart_send("SD card inserted\n");
    send_sd_cmd(SdCmd::CMD0_GO_IDLE_STATE, 0);

    // Make sure device is talking to us
    uint32_t reply;
    uint32_t args = 0;
    args |= 0x01 << 8;  // 2.6 - 3.3v
    args |= 0xa5;       // Check pattern XXX Use random pattern
    uint8_t status = send_sd_cmd(SdCmd::CMD8_SEND_IF_COND, args, reply);

    if( (status & GetStatus__Cmd_Timeout) != 0 ) {
        // SD did not reply to voltage confirmation. Either we can't support it or it's a ver 1 card.
        // The standard also suggests there is no card inserted, but we rely on a separate card detect to eliminate that
        // option.

        cardType = CardType::Sdsc;
        args = 0<<30;           // Cards that don't respond to CMD8_SEND_IF_COND are told we don't support anything above SDSC
    } else {
        uart_send("V2 cards are not yet supported\n");
        return;
    }

    args |= 3<<20;              // We work at 3v3, do mark the range of 3v2 to 3v4.
    unsigned retries = 0;

    static constexpr uint64_t SendOpTimeoutNs = 1'0000'000'000; // 1 second
    static constexpr uint64_t SendOpTimeoutSplit = 50;

    status = send_sd_cmd(SdCmd::ACMD41_SD_SEND_OP_COND, args, reply);

    if( (status & GetStatus__Cmd_Timeout) != 0 ) {
        uart_send( "SD card failed to respond to commands\n" );

        return;
    }

    // The ACMD41_SD_SEND_OP_COND, and *only* it, respond with CMD and CRC set to all 1's. Instead of convulting the hardware for just
    // this one command, we /expect/ that status to have both GetStatus__CmdMismatch and GetStatus__CrcMismatch set.

    reply = 0;
    for( unsigned retries=0; retries<SendOpTimeoutSplit && (reply & (1u<<31))==0; retries++ ) {
        saros.sleep_ns( SendOpTimeoutNs / SendOpTimeoutSplit );
        status = send_sd_cmd(SdCmd::ACMD41_SD_SEND_OP_COND, args, reply);
    }

    if( (reply & (1u<<31))==0 ) {
        uart_send( "SD card not ready in time: response " );
        print_hex( reply );
        uart_send( " status ");
        print_hex( status );
        uart_send( "\n" );

        return;
    }

    uart_send("SD probed: V1 SEND_OP status ");
    print_hex(status);
    uart_send(" reply ");
    print_hex(reply);
    uart_send("\n");

    CID cid;
    status = send_sd_cmd(SdCmd::CMD2_ALL_SEND_CID, 0, cid.raw);

    uart_send("  Manufacturer ID ");
    print_hex(cid.manufacturerId);
    uart_send(" OEM ");
    print_hex(cid.oid);
    uart_send(" product name \"");
    for( char c : cid.productName ) {
        if( c=='\0' )
            break;

        uart_send(c);
    }
    uart_send("\" rev ");
    print_hex(cid.prodRev);
    uart_send(" S/N ");
    print_hex(cid.prodSN1);
    print_hex(cid.prodSN2);
    uart_send(" manufacturing date ");
    print_hex(cid.manufacturingMonth);
    uart_send("/");
    print_hex(cid.manufacturingYear);
    uart_send("\n");

    status = send_sd_cmd(SdCmd::CMD3_SEND_RELATIVE_ADDR, 0, reply);
    if( isError(status) )
        return;

    _cardAddr = reply>>16;

    CSD csd;
    status = send_sd_cmd(SdCmd::CMD9_SEND_CSD, _cardAddr<<16, csd.raw);
    if( isError(status) )
        return;

    uint32_t blockSize = BlockSize;
    switch(csd.v1.csdStructure) {
    case 0:
        {
            // V1 card
            blockSize = 1u << csd.v1.readBlLen;
            uint32_t mult = 1u << (csd.v1.cSizeMult + 2u);
            uint32_t cSize = (csd.v1.cSize_high << 2u) | csd.v1.cSize_low;
            _numBlocks = (cSize+1) * mult;
        }
    }

    uart_send("  SD size: ");
    print_dec(_numBlocks);
    uart_send(" blocks of ");
    print_dec(blockSize);
    uart_send(" bytes = ");
    print_dec( _numBlocks * blockSize / 1024 / 1024 );
    uart_send("MB\n");


    if( blockSize != BlockSize ) {
        uart_send("E: Only 512 bytes block cards are supported\n");

        return;
    }

    /* We're skipping the following stages of init
     *  CMD4 - driver stages:   Undocumented in the simplified specs, and also probably unsopported for an FPGA based impl.
     *                          Also - probably unnecessary for the low frequencies we work at, but we'll never know.
     *  CMD16 set block length: For SDSC the default is defined as 512 bytes, for the others it's the only legal value.
     *                          So our code assumes 512 bytes block and refuses to work otherwise.
     * ACMD6 - wide bus:        TODO Not yet implemented in hardware
     */


    uart_send("  Selecting card\n");
    SdReply1 rep1;
    status = send_sd_cmd( SdCmd::CMD7_DE_SELECT_CARD, _cardAddr<<16, rep1.reply );
    if( isError(status) )
        return;

    _cardType = cardType;
}

void SD::threadMain() noexcept {
    while(true) {
        if( isInserted() ) {
            irq_external_mask( IrqExt__SdCardIn );
            reset_gpio_bits(0, GPO0__SD_CARD_POLARITY);

            uart_send("Initializing SD card\n");

            initCard();

            if( !sd ) {
                uart_send("E: Card initialization failed. Retrying in 1 second\n");
                saros.sleep_ns( 1'000'000'000 );

                continue;
            }

            uart_send("Reading in partition table\n");
            BlockPtr mbr = readBlock(0);
            if( !mbr ) {
                uart_send("E: Failed to read MBR\n");

                continue;
            }
            dump_memory(mbr->data);

            // Disable interrupts, set up the IRQ, and then sleep, which will re-enable interrupts
            Saros::csr_read_clr_bits<Saros::CSR::mstatus>( Saros::MSTATUS__MIE );

            if( !isInserted() ) {
                Saros::csr_read_set_bits<Saros::CSR::mstatus>( Saros::MSTATUS__MIE );
            } else {
                irq_external_unmask( IrqExt__SdCardIn );
                _cardStatusChanged.wait();
            }
        } else {
            uart_send("SD card removed\n");

            // Disable interrupts, set up the IRQ, and then sleep, which will re-enable interrupts
            Saros::csr_read_clr_bits<Saros::CSR::mstatus>( Saros::MSTATUS__MIE );

            set_gpio_bits(0, GPO0__SD_CARD_POLARITY);
            irq_external_unmask( IrqExt__SdCardIn );
            _cardStatusChanged.wait();
        }
    }
}

void SD::init() {
    saros.createThread( [](void *) noexcept { sd.threadMain(); }, nullptr);
}

void SD::irq_handler_insert() noexcept {
    irq_external_mask( IrqExt__SdCardIn );

    sd._cardStatusChanged.signal();
}

void SD::irq_handler_data() noexcept {
    irq_external_mask( IrqExt__SdCardDataIdle );

    sd._dataIdle.signal();
}

void SD::uninit() {
    _cardType = CardType::Uninit;
}


DS::PoolAllocator<SD::Block, SD::BlocksPoolSize> SD::_blocksPool;

// Internal utility functions

[[nodiscard]] static SdReply1 send_app_cmd() {
    SdReply1 cardStatus;
    uint32_t status = send_sd_cmd(SdCmd::APP_CMD, 0, cardStatus.reply);

    if( (status & GetStatus__Cmd_ReplyReceived) && ((status & GetStatus__Cmd_ErrorMask) == 0) && cardStatus.appCmd ) {
        return cardStatus;
    }

    uart_send("  W: APP_CMD needs 2nd  attempt S:");
    print_hex(status);
    uart_send(" R:");
    print_hex(cardStatus.reply);
    uart_send("\n");

    status = send_sd_cmd(SdCmd::APP_CMD, 0, cardStatus.reply);

    return cardStatus;
}

void send_sd_cmd(SdCmd command, uint32_t args) {
    reg_write_32(DeviceId, RegW__SetCmdArgument, args);
    reg_write_32(DeviceId, RegW__SendCmd, static_cast<uint32_t>(command));
}

uint32_t send_sd_cmd(SdCmd command, uint32_t args, uint32_t &reply) {
    if( (static_cast<uint32_t>(command) & APP_CMD_BIT) != 0 ) {
        if( !send_app_cmd().appCmd ) {
            return GetStatus__Cmd_Mismatch;
        }
    }

    reg_write_32(DeviceId, RegW__SetCmdArgument, args);
    reg_write_32(DeviceId, RegW__SendCmd, static_cast<uint32_t>(command) | SetCmd__Reply48);

    uint32_t status;
    do {
       status = reg_read_32(DeviceId, RegR__GetStatus);
    } while( (status & GetStatus__CmdBusy) != 0 );

    reply = reg_read_32(DeviceId, RegR__GetReply0);

    return status;
}

uint32_t send_sd_cmd(SdCmd command, uint32_t args, uint128_t &reply) {
    if( (static_cast<uint32_t>(command) & APP_CMD_BIT) != 0 ) {
        if( !send_app_cmd().appCmd ) {
            return GetStatus__Cmd_Mismatch;
        }
    }

    reg_write_32(DeviceId, RegW__SetCmdArgument, args);
    reg_write_32(DeviceId, RegW__SendCmd, static_cast<uint32_t>(command) & CMD_BITS_MASK | SetCmd__Reply136);

    uint32_t status;
    do {
       status = reg_read_32(DeviceId, RegR__GetStatus);
    } while( (status & GetStatus__CmdBusy) != 0 );

    reply.w0 = reg_read_32(DeviceId, RegR__GetReply0);
    reply.w1 = reg_read_32(DeviceId, RegR__GetReply1);
    reply.w2 = reg_read_32(DeviceId, RegR__GetReply2);
    reply.w3 = reg_read_32(DeviceId, RegR__GetReply3);

    return status;
}
