#include <6502_dbg.hh>

#include <apple2_pager.hh>

#include <saros/saros.h>
#include <saros/sync/event.h>

#include "uart.h"
#include "format.h"
#include "reg.h"

using namespace Apple2;

constexpr uint32_t DeviceNum = 0x83;

constexpr uint32_t Dbg_Status = 0x0000;
    constexpr uint32_t Dbg_Status__Cont = 0x0001;
    constexpr uint32_t Dbg_Status__Halt = 0x0002;
    constexpr uint32_t Dbg_Status__SingleStep = 0x0004;
constexpr uint32_t Dbg_State  = 0x0004;

constexpr uint32_t Dbg_ReadRegA = 0x0010;
constexpr uint32_t Dbg_ReadRegX = 0x0014;
constexpr uint32_t Dbg_ReadRegY = 0x0018;
constexpr uint32_t Dbg_ReadRegS = 0x001c;
constexpr uint32_t Dbg_ReadRegP = 0x0020;

constexpr uint32_t NumBreakpoints = 4;

constexpr uint32_t Dbg_BreakPointBase = 0x8000;

static Saros::Sync::Event debug6502Halted;

namespace {
    struct OpcodeNames {
        const char *name;
        bool write = false;
    };

    constexpr OpcodeNames opcodeNames[] = {
        { "???", false },       //   0
        { "ADC", false },       //   1
        { "AND", false },       //   2
        { "ASL", true },        //   3
        { "BBR0", false },      //   4
        { "BBR1", false },      //   5
        { "BBR2", false },      //   6
        { "BBR3", false },      //   7
        { "BBR4", false },      //   8
        { "BBR5", false },      //   9
        { "BBR6", false },      //  10
        { "BBR7", false },      //  11
        { "BBS0", false },      //  12
        { "BBS1", false },      //  13
        { "BBS2", false },      //  14
        { "BBS3", false },      //  15
        { "BBS4", false },      //  16
        { "BBS5", false },      //  17
        { "BBS6", false },      //  18
        { "BBS7", false },      //  19
        { "BCC", false },       //  20
        { "BCS", false },       //  21
        { "BEQ", false },       //  22
        { "BIT", false },       //  23
        { "BMI", false },       //  24
        { "BNE", false },       //  25
        { "BPL", false },       //  26
        { "BRA", false },       //  27
        { "BRK", false },       //  28
        { "BVC", false },       //  29
        { "BVS", false },       //  30
        { "CLC", false },       //  31
        { "CLD", false },       //  32
        { "CLI", false },       //  33
        { "CLV", false },       //  34
        { "CMP", false },       //  35
        { "CPX", false },       //  36
        { "CPY", false },       //  37
        { "DEC", true },        //  38
        { "DEX", false },       //  39
        { "DEY", false },       //  40
        { "EOR", false },       //  41
        { "INC", true },        //  42
        { "INX", false },       //  43
        { "INY", false },       //  44
        { "JMP", false },       //  45
        { "JSR", false },       //  46
        { "LDA", false },       //  47
        { "LDX", false },       //  48
        { "LDY", false },       //  49
        { "LSR", true },        //  50
        { "NOP", false },       //  51
        { "ORA", false },       //  52
        { "PHA", false },       //  53
        { "PHP", false },       //  54
        { "PHX", false },       //  55
        { "PHY", false },       //  56
        { "PLA", false },       //  57
        { "PLP", false },       //  58
        { "PLX", false },       //  59
        { "PLY", false },       //  60
        { "RMB0", true },       //  61
        { "RMB1", true },       //  62
        { "RMB2", true },       //  63
        { "RMB3", true },       //  64
        { "RMB4", true },       //  65
        { "RMB5", true },       //  66
        { "RMB6", true },       //  67
        { "RMB7", true },       //  68
        { "ROL", true },        //  69
        { "ROR", true },        //  70
        { "RTI", false },       //  71
        { "RTS", false },       //  72
        { "SBC", false },       //  73
        { "SEC", false },       //  74
        { "SED", false },       //  75
        { "SEI", false },       //  76
        { "SMB0", true },       //  77
        { "SMB1", true },       //  78
        { "SMB2", true },       //  79
        { "SMB3", true },       //  80
        { "SMB4", true },       //  81
        { "SMB5", true },       //  82
        { "SMB6", true },       //  83
        { "SMB7", true },       //  84
        { "STA", true },        //  85
        { "STP", false },       //  86
        { "STX", true },        //  87
        { "STY", true },        //  88
        { "STZ", true },        //  89
        { "TAX", false },       //  90
        { "TAY", false },       //  91
        { "TRB", true },        //  92
        { "TSB", true },        //  93
        { "TSX", false },       //  94
        { "TXA", false },       //  95
        { "TXS", false },       //  96
        { "TYA", false },       //  97
        { "WAI", false },       //  98
    };

    // Operand displays
    static void printMemOperand(uint16_t addr, bool write) {
        uart_send("   ($");
        print_hex( *translateAddr(addr, write) );
        uart_send(")");
    }

    static uint8_t fetch8(uint16_t addr) {
        return *translateAddr(addr, false);
    }
    static uint16_t fetch16zp(uint8_t addr) {
        uint16_t res = *translateAddr((addr+1) & 0xff, false);
        res <<= 8;
        res |= *translateAddr(addr, false);

        return res;
    }
    static uint16_t fetch16(uint16_t addr) {
        uint16_t res = *translateAddr(addr+1, false);
        res <<= 8;
        res |= *translateAddr(addr, false);

        return res;
    }

    void oprAbs(uint16_t pc, bool write) {
        uint16_t addr = fetch16(pc + 1);

        uart_send(" $");
        print_hex(addr);

        printMemOperand(addr, write);
    }
    void oprAbsXInd(uint16_t pc, bool write) {
        uint16_t addr = fetch16(pc + 1);

        uart_send(" ($");
        print_hex(addr);
        uart_send(",X) = ($");
        uint16_t x = reg_read_32(DeviceNum, Dbg_ReadRegX );
        addr += x;
        print_hex(addr + x);
        uart_send(") -> $");
        
        uint16_t pointed = *translateAddr(addr + 1, false);
        pointed <<= 8;
        pointed |= *translateAddr(addr, false);

        print_hex(pointed);

        printMemOperand(pointed, write);
    }
    void oprAbsX(uint16_t pc, bool write) {
        uint16_t addr = fetch16(pc + 1);

        uart_send(" $");
        print_hex(addr);
        uart_send(",X = $");
        addr += reg_read_32(DeviceNum, Dbg_ReadRegX );
        print_hex(addr);

        printMemOperand(addr, write);
    }
    void oprAbsY(uint16_t pc, bool write) {
        uint16_t addr = fetch16(pc + 1);

        uart_send(" $");
        print_hex(addr);
        uart_send(",Y = $");
        addr += reg_read_32(DeviceNum, Dbg_ReadRegY );
        print_hex(addr);

        printMemOperand(addr, write);
    }
    void oprAbsInd(uint16_t pc, bool write) {
        uint16_t addr = fetch16(pc + 1);

        uart_send(" ($");
        print_hex(addr);
        uart_send(") = $");

        addr = fetch16(addr);
        print_hex(addr);
    }
    void oprA(uint16_t pc, bool write) {}
    void oprImm(uint16_t pc, bool write) {
        uint8_t value = fetch8(pc + 1);

        uart_send(" #$");
        print_hex(value);
    }
    void oprNone(uint16_t pc, bool write) {}
    void oprPcRel(uint16_t pc, bool write) {
        auto value = static_cast<int8_t>( fetch8(pc + 1) );
        uint16_t dst = pc + 2 + value;

        uart_send(" $");
        print_hex(dst);
    }
    void oprStack(uint16_t pc, bool write) {}
    void oprZp(uint16_t pc, bool write) {
        uint8_t addr = fetch8(pc + 1);

        uart_send(" $");
        print_hex(addr);

        printMemOperand(addr, write);
    }
    void oprZpXInd(uint16_t pc, bool write) {
        uint8_t addr = fetch8(pc + 1);

        uart_send(" ($");
        print_hex(addr);
        uart_send(",X) = ($");
        addr += reg_read_32(DeviceNum, Dbg_ReadRegX );
        print_hex(addr);
        uart_send(") = $");
        uint16_t dst = fetch16zp(addr);
        print_hex(dst);

        printMemOperand(dst, write);
    }
    void oprZpX(uint16_t pc, bool write) {
        uint8_t addr = fetch8(pc + 1);

        uart_send(" $");
        print_hex(addr);
        uart_send(",X = $");
        addr += reg_read_32(DeviceNum, Dbg_ReadRegX );
        print_hex(addr);

        printMemOperand(addr, write);
    }
    void oprZpY(uint16_t pc, bool write) {
        uint8_t addr = fetch8(pc + 1);

        uart_send(" $");
        print_hex(addr);
        uart_send(",Y = $");
        addr += reg_read_32(DeviceNum, Dbg_ReadRegY );
        print_hex(addr);

        printMemOperand(addr, write);
    }
    void oprZpInd(uint16_t pc, bool write) {
        uint8_t addr = fetch8(pc + 1);

        uart_send(" ($");
        print_hex(addr);
        uart_send(") = $");
        uint16_t dst = fetch16zp(addr);
        print_hex(dst);

        printMemOperand(dst, write);
    }
    void oprZpIndY(uint16_t pc, bool write) {
        uint8_t addr = fetch8(pc + 1);

        uart_send(" ($");
        print_hex(addr);
        uart_send("),Y = $");
        uint16_t dst = fetch16zp(addr);
        print_hex(dst);
        uart_send(",Y = $");
        dst += reg_read_32(DeviceNum, Dbg_ReadRegY );
        print_hex(dst);

        printMemOperand(dst, write);
    }

    struct Opcode {
        unsigned index;                         // Index to opcodeNames table
        void (* argsParse)(uint16_t, bool);     // Callback for displaying the arguments
    };

    Opcode opcodes[] = {
        [0x00] = {28, oprStack   },  // BRK s
        [0x01] = {52, oprZpXInd  },  // ORA (zp,x)
        [0x02] = { 0, oprNone    },  // ??? (unused)
        [0x03] = { 0, oprNone    },  // ??? (unused)
#if WDC6502
        [0x04] = {93, oprZp      },  // TSB zp
#else
        [0x04] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x05] = {52, oprZp      },  // ORA zp
        [0x06] = { 3, oprZp      },  // ASL zp
#if WDC6502
        [0x07] = {61, oprZp      },  // RMB0 zp
#else
        [0x07] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x08] = {54, oprStack   },  // PHP s
        [0x09] = {52, oprImm     },  // ORA #
        [0x0a] = { 3, oprA       },  // ASL A
        [0x0b] = { 0, oprNone    },  // ??? (unused)
#if WDC6502
        [0x0c] = {93, oprAbs     },  // TSB a
#else
        [0x0c] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x0d] = {52, oprAbs     },  // ORA a
        [0x0e] = { 3, oprAbs     },  // ASL a
#if WDC6502
        [0x0f] = { 4, oprNone    },  // BBR0 r
#else
        [0x0f] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x10] = {26, oprPcRel   },  // BPL r
        [0x11] = {52, oprZpIndY  },  // ORA (zp),y
#if WDC6502
        [0x12] = {52, oprZpInd   },  // ORA (zp)
#else
        [0x12] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x13] = { 0, oprNone    },  // ??? (unused)
#if WDC6502
        [0x14] = {92, oprZp      },  // TRB zp
#else
        [0x14] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x15] = {52, oprZpX     },  // ORA zp,x
        [0x16] = { 3, oprZpX     },  // ASL zp,x
#if WDC6502
        [0x17] = {62, oprZp      },  // RMB1 zp
#else
        [0x17] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x18] = {31, oprNone    },  // CLC i
        [0x19] = {52, oprAbsY    },  // ORA a,y
#if WDC6502
        [0x1a] = {42, oprA       },  // INC A
#else
        [0x1a] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x1b] = { 0, oprNone    },  // ??? (unused)
#if WDC6502
        [0x1c] = {92, oprAbs     },  // TRB a
#else
        [0x1c] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x1d] = {52, oprAbsX    },  // ORA a,x
        [0x1e] = { 3, oprAbsX    },  // ASL a,x
#if WDC6502
        [0x1f] = { 5, oprNone    },  // BBR1 r
#else
        [0x1f] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x20] = {46, oprAbs     },  // JSR a
        [0x21] = { 2, oprZpXInd  },  // AND (zp,x)
        [0x22] = { 0, oprNone    },  // ??? (unused)
        [0x23] = { 0, oprNone    },  // ??? (unused)
        [0x24] = {23, oprZp      },  // BIT zp
        [0x25] = { 2, oprZp      },  // AND zp
        [0x26] = {69, oprZp      },  // ROL zp
#if WDC6502
        [0x27] = {63, oprZp      },  // RMB2 zp
#else
        [0x27] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x28] = {58, oprStack   },  // PLP s
        [0x29] = { 2, oprImm     },  // AND #
        [0x2a] = {69, oprA       },  // ROL A
        [0x2b] = { 0, oprNone    },  // ??? (unused)
        [0x2c] = {23, oprAbs     },  // BIT a
        [0x2d] = { 2, oprAbs     },  // AND a
        [0x2e] = {69, oprAbs     },  // ROL a
#if WDC6502
        [0x2f] = { 6, oprNone    },  // BBR2 r
#else
        [0x2f] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x30] = {24, oprPcRel   },  // BMI r
        [0x31] = { 2, oprZpIndY  },  // AND (zp),y
#if WDC6502
        [0x32] = { 2, oprZpInd   },  // AND (zp)
#else
        [0x32] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x33] = { 0, oprNone    },  // ??? (unused)
#if WDC6502
        [0x34] = {23, oprZpX     },  // BIT zp,x
#else
        [0x34] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x35] = { 2, oprZpX     },  // AND zp,x
        [0x36] = {69, oprZpX     },  // ROL zp,x
#if WDC6502
        [0x37] = {64, oprZp      },  // RMB3 zp
#else
        [0x37] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x38] = {74, oprNone    },  // SEC i
        [0x39] = { 2, oprAbsY    },  // AND a,y
#if WDC6502
        [0x3a] = {38, oprA       },  // DEC A
#else
        [0x3a] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x3b] = { 0, oprNone    },  // ??? (unused)
#if WDC6502
        [0x3c] = {23, oprAbsX    },  // BIT a,x
#else
        [0x3c] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x3d] = { 2, oprAbsX    },  // AND a,x
        [0x3e] = {69, oprAbsX    },  // ROL a,x
#if WDC6502
        [0x3f] = { 7, oprNone    },  // BBR3 r
#else
        [0x3f] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x40] = {71, oprStack   },  // RTI s
        [0x41] = {41, oprZpXInd  },  // EOR (zp,x)
        [0x42] = { 0, oprNone    },  // ??? (unused)
        [0x43] = { 0, oprNone    },  // ??? (unused)
        [0x44] = { 0, oprNone    },  // ??? (unused)
        [0x45] = {41, oprZp      },  // EOR zp
        [0x46] = {50, oprZp      },  // LSR zp
#if WDC6502
        [0x47] = {65, oprZp      },  // RMB4 zp
#else
        [0x47] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x48] = {53, oprStack   },  // PHA s
        [0x49] = {41, oprImm     },  // EOR #
        [0x4a] = {50, oprA       },  // LSR A
        [0x4b] = { 0, oprNone    },  // ??? (unused)
        [0x4c] = {45, oprAbs     },  // JMP a
        [0x4d] = {41, oprAbs     },  // EOR a
        [0x4e] = {50, oprAbs     },  // LSR a
#if WDC6502
        [0x4f] = { 8, oprNone    },  // BBR4 r
#else
        [0x4f] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x50] = {29, oprPcRel   },  // BVC r
        [0x51] = {41, oprZpIndY  },  // EOR (zp),y
#if WDC6502
        [0x52] = {41, oprZpInd   },  // EOR (zp)
#else
        [0x52] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x53] = { 0, oprNone    },  // ??? (unused)
        [0x54] = { 0, oprNone    },  // ??? (unused)
        [0x55] = {41, oprZpX     },  // EOR zp,x
        [0x56] = {50, oprZpX     },  // LSR zp,x
#if WDC6502
        [0x57] = {66, oprZp      },  // RMB5 zp
#else
        [0x57] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x58] = {33, oprNone    },  // CLI i
        [0x59] = {41, oprAbsY    },  // EOR a,y
#if WDC6502
        [0x5a] = {56, oprStack   },  // PHY s
#else
        [0x5a] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x5b] = { 0, oprNone    },  // ??? (unused)
        [0x5c] = { 0, oprNone    },  // ??? (unused)
        [0x5d] = {41, oprAbsX    },  // EOR a,x
        [0x5e] = {50, oprAbsX    },  // LSR a,x
#if WDC6502
        [0x5f] = { 9, oprNone    },  // BBR5 r
#else
        [0x5f] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x60] = {72, oprStack   },  // RTS s
        [0x61] = { 1, oprZpXInd  },  // ADC (zp,x)
        [0x62] = { 0, oprNone    },  // ??? (unused)
        [0x63] = { 0, oprNone    },  // ??? (unused)
#if WDC6502
        [0x64] = {89, oprZp      },  // STZ zp
#else
        [0x64] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x65] = { 1, oprZp      },  // ADC zp
        [0x66] = {70, oprZp      },  // ROR zp
#if WDC6502
        [0x67] = {67, oprZp      },  // RMB6 zp
#else
        [0x67] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x68] = {57, oprStack   },  // PLA s
        [0x69] = { 1, oprImm     },  // ADC #
        [0x6a] = {70, oprA       },  // ROR A
        [0x6b] = { 0, oprNone    },  // ??? (unused)
        [0x6c] = {45, oprAbsInd  },  // JMP (a)
        [0x6d] = { 1, oprAbs     },  // ADC a
        [0x6e] = {70, oprAbs     },  // ROR a
#if WDC6502
        [0x6f] = {10, oprNone    },  // BBR6 r
#else
        [0x6f] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x70] = {30, oprPcRel   },  // BVS r
        [0x71] = { 1, oprZpIndY  },  // ADC (zp),y
#if WDC6502
        [0x72] = { 1, oprZpInd   },  // ADC (zp)
#else
        [0x72] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x73] = { 0, oprNone    },  // ??? (unused)
#if WDC6502
        [0x74] = {89, oprZpX     },  // STZ zp,x
#else
        [0x74] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x75] = { 1, oprZpX     },  // ADC zp,x
        [0x76] = {70, oprZpX     },  // ROR zp,x
#if WDC6502
        [0x77] = {68, oprZp      },  // RMB7 zp
#else
        [0x77] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x78] = {76, oprNone    },  // SEI i
        [0x79] = { 1, oprAbsY    },  // ADC a,y
#if WDC6502
        [0x7a] = {60, oprStack   },  // PLY s
#else
        [0x7a] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x7b] = { 0, oprNone    },  // ??? (unused)
#if WDC6502
        [0x7c] = {45, oprAbsXInd },  // JMP (a,x)
#else
        [0x7c] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x7d] = { 1, oprAbsX    },  // ADC a,x
        [0x7e] = {70, oprAbsX    },  // ROR a,x
#if WDC6502
        [0x7f] = {11, oprNone    },  // BBR7 r
#else
        [0x7f] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
#if WDC6502
        [0x80] = {27, oprPcRel   },  // BRA r
#else
        [0x80] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x81] = {85, oprZpXInd  },  // STA (zp,x)
        [0x82] = { 0, oprNone    },  // ??? (unused)
        [0x83] = { 0, oprNone    },  // ??? (unused)
        [0x84] = {88, oprZp      },  // STY zp
        [0x85] = {85, oprZp      },  // STA zp
        [0x86] = {87, oprZp      },  // STX zp
#if WDC6502
        [0x87] = {77, oprZp      },  // SMB0 zp
#else
        [0x87] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x88] = {40, oprNone    },  // DEY i
#if WDC6502
        [0x89] = {23, oprImm     },  // BIT #
#else
        [0x89] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x8a] = {95, oprNone    },  // TXA i
        [0x8b] = { 0, oprNone    },  // ??? (unused)
        [0x8c] = {88, oprAbs     },  // STY a
        [0x8d] = {85, oprAbs     },  // STA a
        [0x8e] = {87, oprAbs     },  // STX a
#if WDC6502
        [0x8f] = {12, oprNone    },  // BBS0 r
#else
        [0x8f] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x90] = {20, oprPcRel   },  // BCC r
        [0x91] = {85, oprZpIndY  },  // STA (zp),y
#if WDC6502
        [0x92] = {85, oprZpInd   },  // STA (zp)
#else
        [0x92] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x93] = { 0, oprNone    },  // ??? (unused)
        [0x94] = {88, oprZpX     },  // STY zp,x
        [0x95] = {85, oprZpX     },  // STA zp,x
        [0x96] = {87, oprZpY     },  // STX zp,y
#if WDC6502
        [0x97] = {78, oprZp      },  // SMB1 zp
#else
        [0x97] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x98] = {97, oprNone    },  // TYA i
        [0x99] = {85, oprAbsY    },  // STA a,y
        [0x9a] = {96, oprNone    },  // TXS i
        [0x9b] = { 0, oprNone    },  // ??? (unused)
#if WDC6502
        [0x9c] = {89, oprAbs     },  // STZ a
#else
        [0x9c] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0x9d] = {85, oprAbsX    },  // STA a,x
#if WDC6502
        [0x9e] = {89, oprAbsX    },  // STZ a,x
#else
        [0x9e] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
#if WDC6502
        [0x9f] = {13, oprNone    },  // BBS1 r
#else
        [0x9f] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xa0] = {49, oprImm     },  // LDY #
        [0xa1] = {47, oprZpXInd  },  // LDA (zp,x)
        [0xa2] = {48, oprImm     },  // LDX #
        [0xa3] = { 0, oprNone    },  // ??? (unused)
        [0xa4] = {49, oprZp      },  // LDY zp
        [0xa5] = {47, oprZp      },  // LDA zp
        [0xa6] = {48, oprZp      },  // LDX zp
#if WDC6502
        [0xa7] = {79, oprZp      },  // SMB2 zp
#else
        [0xa7] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xa8] = {91, oprNone    },  // TAY i
        [0xa9] = {47, oprImm     },  // LDA #
        [0xaa] = {90, oprNone    },  // TAX i
        [0xab] = { 0, oprNone    },  // ??? (unused)
        [0xac] = {49, oprAbs     },  // LDY a
        [0xad] = {47, oprAbs     },  // LDA a
        [0xae] = {48, oprAbs     },  // LDX a
#if WDC6502
        [0xaf] = {14, oprNone    },  // BBS2 r
#else
        [0xaf] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xb0] = {21, oprPcRel   },  // BCS r
        [0xb1] = {47, oprZpIndY  },  // LDA (zp),y
#if WDC6502
        [0xb2] = {47, oprZpInd   },  // LDA (zp)
#else
        [0xb2] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xb3] = { 0, oprNone    },  // ??? (unused)
        [0xb4] = {49, oprZpX     },  // LDY zp,x
        [0xb5] = {47, oprZpX     },  // LDA zp,x
        [0xb6] = {48, oprZpY     },  // LDX zp,y
#if WDC6502
        [0xb7] = {80, oprZp      },  // SMB3 zp
#else
        [0xb7] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xb8] = {34, oprNone    },  // CLV i
        [0xb9] = {47, oprAbsY    },  // LDA a,y
        [0xba] = {94, oprNone    },  // TSX i
        [0xbb] = { 0, oprNone    },  // ??? (unused)
        [0xbc] = {49, oprAbsX    },  // LDY a,x
        [0xbd] = {47, oprAbsX    },  // LDA a,x
        [0xbe] = {48, oprAbsY    },  // LDX a,y
#if WDC6502
        [0xbf] = {15, oprNone    },  // BBS3 r
#else
        [0xbf] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xc0] = {37, oprImm     },  // CPY #
        [0xc1] = {35, oprZpXInd  },  // CMP (zp,x)
        [0xc2] = { 0, oprNone    },  // ??? (unused)
        [0xc3] = { 0, oprNone    },  // ??? (unused)
        [0xc4] = {37, oprZp      },  // CPY zp
        [0xc5] = {35, oprZp      },  // CMP zp
        [0xc6] = {38, oprZp      },  // DEC zp
#if WDC6502
        [0xc7] = {81, oprZp      },  // SMB4 zp
#else
        [0xc7] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xc8] = {44, oprNone    },  // INY i
        [0xc9] = {35, oprImm     },  // CMP #
        [0xca] = {39, oprNone    },  // DEX i
#if WDC6502
        [0xcb] = {98, oprNone    },  // WAI i
#else
        [0xcb] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xcc] = {37, oprAbs     },  // CPY a
        [0xcd] = {35, oprAbs     },  // CMP a
        [0xce] = {38, oprAbs     },  // DEC a
#if WDC6502
        [0xcf] = {16, oprNone    },  // BBS4 r
#else
        [0xcf] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xd0] = {25, oprPcRel   },  // BNE r
        [0xd1] = {35, oprZpIndY  },  // CMP (zp),y
#if WDC6502
        [0xd2] = {35, oprZpInd   },  // CMP (zp)
#else
        [0xd2] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xd3] = { 0, oprNone    },  // ??? (unused)
        [0xd4] = { 0, oprNone    },  // ??? (unused)
        [0xd5] = {35, oprZpX     },  // CMP zp,x
        [0xd6] = {38, oprZpX     },  // DEC zp,x
#if WDC6502
        [0xd7] = {82, oprZp      },  // SMB5 zp
#else
        [0xd7] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xd8] = {32, oprNone    },  // CLD i
        [0xd9] = {35, oprAbsY    },  // CMP a,y
#if WDC6502
        [0xda] = {55, oprStack   },  // PHX s
#else
        [0xda] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
#if WDC6502
        [0xdb] = {86, oprNone    },  // STP i
#else
        [0xdb] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xdc] = { 0, oprNone    },  // ??? (unused)
        [0xdd] = {35, oprAbsX    },  // CMP a,x
        [0xde] = {38, oprAbsX    },  // DEC a,x
#if WDC6502
        [0xdf] = {17, oprNone    },  // BBS5 r
#else
        [0xdf] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xe0] = {36, oprImm     },  // CPX #
        [0xe1] = {73, oprZpXInd  },  // SBC (zp,x)
        [0xe2] = { 0, oprNone    },  // ??? (unused)
        [0xe3] = { 0, oprNone    },  // ??? (unused)
        [0xe4] = {36, oprZp      },  // CPX zp
        [0xe5] = {73, oprZp      },  // SBC zp
        [0xe6] = {42, oprZp      },  // INC zp
#if WDC6502
        [0xe7] = {83, oprZp      },  // SMB6 zp
#else
        [0xe7] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xe8] = {43, oprNone    },  // INX i
        [0xe9] = {73, oprImm     },  // SBC #
        [0xea] = {51, oprNone    },  // NOP i
        [0xeb] = { 0, oprNone    },  // ??? (unused)
        [0xec] = {36, oprAbs     },  // CPX a
        [0xed] = {73, oprAbs     },  // SBC a
        [0xee] = {42, oprAbs     },  // INC a
#if WDC6502
        [0xef] = {18, oprNone    },  // BBS6 r
#else
        [0xef] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xf0] = {22, oprPcRel   },  // BEQ r
        [0xf1] = {73, oprZpIndY  },  // SBC (zp),y
#if WDC6502
        [0xf2] = {73, oprZpInd   },  // SBC (zp)
#else
        [0xf2] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xf3] = { 0, oprNone    },  // ??? (unused)
        [0xf4] = { 0, oprNone    },  // ??? (unused)
        [0xf5] = {73, oprZpX     },  // SBC zp,x
        [0xf6] = {42, oprZpX     },  // INC zp,x
#if WDC6502
        [0xf7] = {84, oprZp      },  // SMB7 zp
#else
        [0xf7] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xf8] = {75, oprNone    },  // SED i
        [0xf9] = {73, oprAbsY    },  // SBC a,y
#if WDC6502
        [0xfa] = {59, oprStack   },  // PLX s
#else
        [0xfa] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
        [0xfb] = { 0, oprNone    },  // ??? (unused)
        [0xfc] = { 0, oprNone    },  // ??? (unused)
        [0xfd] = {73, oprAbsX    },  // SBC a,x
        [0xfe] = {42, oprAbsX    },  // INC a,x
#if WDC6502
        [0xff] = {19, oprNone    },  // BBS7 r
#else
        [0xff] = { 0, oprNone    },  // ??? (W65C02S-only, unused without WDC6502)
#endif
    };
}

static void debugger_loop(void *) noexcept {
    uart_send("Debugger thread started\n");

    while(true) {
        irq_external_unmask(IrqExt__6502Debug);
        debug6502Halted.wait();

        // Handle the debugger
        uint32_t state = reg_read_32(DeviceNum, Dbg_State);
        uint16_t pc = state & 0xffff;
        uart_send("DBG: A:");
        print_hex( reg_read_32(DeviceNum, Dbg_ReadRegA ) );
        uart_send(" X:");
        print_hex( reg_read_32(DeviceNum, Dbg_ReadRegX ) );
        uart_send(" Y:");
        print_hex( reg_read_32(DeviceNum, Dbg_ReadRegY ) );
        uart_send(" S:");
        print_hex( reg_read_32(DeviceNum, Dbg_ReadRegS ) );
        uart_send(" P:");
        uint32_t regP = reg_read_32(DeviceNum, Dbg_ReadRegP );
        print_hex( regP );

        if( regP & 0x80 )
            uart_send(" N");
        else
            uart_send(" -");

        if( regP & 0x40 )
            uart_send("V");
        else
            uart_send("-");

        if( regP & 0x20 )
            uart_send("1");
        else
            uart_send("-");

        if( regP & 0x10 )
            uart_send("B");
        else
            uart_send("-");

        if( regP & 0x08 )
            uart_send("D");
        else
            uart_send("-");

        if( regP & 0x04 )
            uart_send("I");
        else
            uart_send("-");

        if( regP & 0x02 )
            uart_send("Z");
        else
            uart_send("-");

        if( regP & 0x01 )
            uart_send("C  ");
        else
            uart_send("-  ");

        print_hex(pc);
        uart_send(": ");

        uint8_t opcode = *translateAddr(pc, false);
        const Opcode &decodedOp = opcodes[opcode];
        const OpcodeNames &opcodeName = opcodeNames[ decodedOp.index ];
        uart_send( opcodeName.name );

        decodedOp.argsParse(pc, opcodeName.write);

        uart_send("\n");

        reg_write_32(DeviceNum, Dbg_Status, Dbg_Status__Cont | Dbg_Status__SingleStep);

        debug6502Halted.clear();
    }
}

void init_debugger() {
    saros.createThread( debugger_loop, nullptr, "Debugger thread"_fs );
}

void irq_debug_6502() {
    irq_external_mask(IrqExt__6502Debug);
    debug6502Halted.set();
}

void set_breakpoint( uint8_t bp, uint16_t address, uint8_t state, uint8_t mask ) {
    reg_write_32(
            DeviceNum, Dbg_BreakPointBase + bp * 4,
            mask<<28 | state<<24 | address );
}
