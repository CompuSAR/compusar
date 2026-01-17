#include "sd.h"

#include "reg.h"

namespace {
// Write registers
constexpr uint32_t RegW__SetCmdArgument                 = 0x0000;
constexpr uint32_t RegW__SetCmd                         = 0x0004;
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

constexpr uint32_t RegR__GetReply0                      = 0x0010;
constexpr uint32_t RegR__GetReply1                      = 0x0014;
constexpr uint32_t RegR__GetReply2                      = 0x0018;
constexpr uint32_t RegR__GetReply3                      = 0x001c;

static constexpr uint32_t DeviceId = 6;
}
