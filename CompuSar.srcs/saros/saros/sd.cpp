#include "sd.h"

#include "reg.h"

namespace {
constexpr uint32_t Reg__SetCmdArgument                  = 0x0000;
constexpr uint32_t Reg__SetCmd                          = 0x0004;
    constexpr uint32_t SetCmd__Reply48                  = 0x00000100;
    constexpr uint32_t SetCmd__Reply136                 = 0x00000300;
}
