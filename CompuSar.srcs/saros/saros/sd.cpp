#include "sd.h"

#include "saros/saros.h"

#include "format.h"
#include "gpio.h"
#include "irq.h"
#include "reg.h"
#include "uart.h"

/* In this file, any comment referencing a standard section refers to "SD Physical Layer Simplified Specification Ver 9.00"
 */

namespace {
// Write registers
constexpr uint32_t RegW__SetCmdArgument                 = 0x0000;
constexpr uint32_t RegW__SendCmd                        = 0x0004;
    constexpr uint32_t SetCmd__Reply48                  = 0x00000100;
    constexpr uint32_t SetCmd__Reply136                 = 0x00000300;

// Read registers
constexpr uint32_t RegR__GetStatus                      = 0x0000;
    constexpr uint32_t GetStatus__Busy                  = 0x80000000;

    constexpr uint32_t GetStatus__ReplyReceived         = 0x00000001;
    constexpr uint32_t GetStatus__Timeout               = 0x00000010;
    constexpr uint32_t GetStatus__CmdMismatch           = 0x00000020;
    constexpr uint32_t GetStatus__CrcMismatch           = 0x00000040;
    constexpr uint32_t GetStatus__InvalidReplyBit       = 0x00000080;
    constexpr uint32_t GetStatus__ErrorMask             = 0x000000f0;

constexpr uint32_t RegR__GetReply0                      = 0x0010;
constexpr uint32_t RegR__GetReply1                      = 0x0014;
constexpr uint32_t RegR__GetReply2                      = 0x0018;
constexpr uint32_t RegR__GetReply3                      = 0x001c;

static constexpr uint32_t DeviceId = 6;
}

static constexpr uint8_t APP_CMD_BIT = 1<<7;
static constexpr uint8_t CMD_BITS_MASK = (1<<6) - 1;
enum class SdCmd : uint8_t {
    GO_IDLE_STATE = 0,
    SEND_IF_COND = 8,
    READ_SINGLE_BLOCK = 17,
    APP_CMD = 55,

    SD_SEND_OP_COND = 41 | APP_CMD_BIT,
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

namespace {
    SD sd;
};

static void send_sd_cmd(SdCmd command, uint32_t args);
[[nodiscard]] static uint32_t send_sd_cmd(SdCmd command, uint32_t args, uint32_t &reply);

void SD::initCard() {
    // Implement the init state machine described in section 4.2.3

    // Reset the SD to power-on state, regardless of pervious state
    uart_send("SD card inserted\n");
    send_sd_cmd(SdCmd::GO_IDLE_STATE, 0);

    // Make sure device is talking to us
    uint32_t reply;
    uint32_t args = 0;
    args |= 0x01 << 8;  // 2.6 - 3.3v
    args |= 0xa5;       // Check pattern XXX Use random pattern
    uint8_t status = send_sd_cmd(SdCmd::SEND_IF_COND, args, reply);

    if( (status & GetStatus__Timeout) != 0 ) {
        // SD did not reply to voltage confirmation. Either we can't support it or it's a ver 1 card.
        // The standard also suggests there is no card inserted, but we rely on a separate card detect to eliminate that
        // option.

        _cardType = CardType::Sdsc;
        args = 0<<30;           // Cards that don't respond to SEND_IF_COND are told we don't support anything above SDSC
    } else {
        uart_send("V2 cards are not yet supported\n");
        return;
    }

    args |= 3<<20;              // We work at 3v3, do mark the range of 3v2 to 3v4.
    unsigned retries = 0;

    static constexpr uint64_t SendOpTimeoutNs = 1'0000'000'000; // 1 second
    static constexpr uint64_t SendOpTimeoutSplit = 50;

    status = send_sd_cmd(SdCmd::SD_SEND_OP_COND, args, reply);

    if( (status & GetStatus__Timeout) != 0 ) {
        uart_send( "SD card failed to respond to commands\n" );

        return;
    }

    // The SD_SEND_OP_COND, and *only* it, respond with CMD and CRC set to all 1's. Instead of convulting the hardware for just
    // this one command, we /expect/ that status to have both GetStatus__CmdMismatch and GetStatus__CrcMismatch set.

    for( unsigned retries=0; retries<SendOpTimeoutSplit && (reply & (1u<<31))==0; retries++ ) {
        saros.sleep_ns( SendOpTimeoutNs / SendOpTimeoutSplit );
        status = send_sd_cmd(SdCmd::SD_SEND_OP_COND, args, reply);
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

    return;

    uart_send("Negotiate voltage: status ");
    print_hex(status);
    uart_send(" reply ");
    print_hex(reply);
    uart_send("\n");

    status = send_sd_cmd(SdCmd::APP_CMD, 0, reply);
    uart_send("App CMD: status ");
    print_hex(status);
    uart_send(" reply ");
    print_hex(reply);
    uart_send("\n");
}

void SD::threadMain() noexcept {
    while(true) {
        if( (read_gpio(0) & GPI0__SD_CARD_IN_N) == 0 ) {
            irq_external_mask( IrqExt__SdCard );
            reset_gpio_bits(0, GPO0__SD_CARD_POLARITY);

            uart_send("Initializing SD card\n");

            initCard();

            // Disable interrupts, set up the IRQ, and then sleep, which will re-enable interrupts
            Saros::csr_read_clr_bits<Saros::CSR::mstatus>( Saros::MSTATUS__MIE );

            irq_external_unmask( IrqExt__SdCard );
            _cardStatusChanged.wait();
        } else {
            uart_send("SD card removed\n");

            // Disable interrupts, set up the IRQ, and then sleep, which will re-enable interrupts
            Saros::csr_read_clr_bits<Saros::CSR::mstatus>( Saros::MSTATUS__MIE );

            set_gpio_bits(0, GPO0__SD_CARD_POLARITY);
            irq_external_unmask( IrqExt__SdCard );
            _cardStatusChanged.wait();
        }
    }
}

void SD::init() {
    saros.createThread( [](void *) noexcept { sd.threadMain(); }, nullptr);
}

void SD::irq_handler() noexcept {
    irq_external_mask( IrqExt__SdCard );

    sd._cardStatusChanged.signal();
}

[[nodiscard]] static SdReply1 send_app_cmd() {
    SdReply1 cardStatus;
    uint32_t status = send_sd_cmd(SdCmd::APP_CMD, 0, cardStatus.reply);

    if( (status & GetStatus__ReplyReceived) && ((status & GetStatus__ErrorMask) == 0) && cardStatus.appCmd ) {
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
            return GetStatus__CmdMismatch;
        }
    }

    reg_write_32(DeviceId, RegW__SetCmdArgument, args);
    reg_write_32(DeviceId, RegW__SendCmd, static_cast<uint32_t>(command) & CMD_BITS_MASK | SetCmd__Reply48);

    uint32_t status;
    do {
       status = reg_read_32(DeviceId, RegR__GetStatus);
    } while( (status & GetStatus__Busy) != 0 );

    reply = reg_read_32(DeviceId, RegR__GetReply0);

    return status;
}

