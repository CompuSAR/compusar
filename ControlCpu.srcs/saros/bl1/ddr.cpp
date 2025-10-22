#include "ddr.h"

#include "format.h"
#include "gpio.h"
#include "irq.h"
#include "memory.h"
#include "reg.h"
#include "uart.h"

namespace {
static constexpr uint32_t BankBits = 3;
static constexpr uint32_t AddrBits = 14;

enum class DdrCommands {
    ModeRegisterSet     = 0x0,
    Refresh             = 0x1,
    Precharge           = 0x2,
    BankActivate        = 0x3,
    Write               = 0x4,
    Read                = 0x5,
    Calibrate           = 0x6,
    NoOperation         = 0x7,
};

static constexpr int DdrDevice = 1;

enum DdrRegister {
    DdrControl                  = 0x0000,
    DdrOverrideCommand          = 0x0004,
    DdrOverrideAddress          = 0x0008,
    DdrReadOp                   = 0x000c,
    DdrIncDelay                 = 0x0010,
};

static constexpr uint32_t DdrCtrl_ResetAll    = 0x0000;
static constexpr uint32_t DdrCtrl_nMemReset   = 0x0001;
static constexpr uint32_t DdrCtrl_nPhyReset   = 0x0002;
static constexpr uint32_t DdrCtrl_nCtrlReset  = 0x0004;
static constexpr uint32_t DdrCtrl_nBypass     = 0x0008;
static constexpr uint32_t DdrCtrl_Odt         = 0x0010;
static constexpr uint32_t DdrCtrl_Cke         = 0x0020;
static constexpr uint32_t DdrCtrl_WriteLevel  = 0x0040;
static constexpr uint32_t DdrCtrl_OutDqs      = 0x0080;

static void ddr_control(uint32_t ctrl) {
    reg_write_32(DdrDevice, DdrControl, ctrl);
}

void override_command(DdrCommands cmd) {
    fence();
    reg_write_32(DdrDevice, DdrOverrideCommand, static_cast<uint32_t>(cmd));
}

constexpr uint32_t composeDdrAddress(uint32_t bank, uint32_t address) {
    return bank<<(32-BankBits) | address&((1<<AddrBits) - 1);
}

void write_mode_reg0(uint32_t bl, uint32_t cl, uint32_t bt, bool dllReset, uint32_t writeRecovery, bool prechardPd) {
    uint32_t value = 0; // Register 0

    // Burst length
    value |= bl;

    // CAS latency
    value |= (cl&1) << 2;
    value |= (cl&0xe) << (4-1);

    // Read burst type
    value |= bt << 3;

    // DLL reset
    value |= dllReset ? 1<<8 : 0;

    // Write recovery
    value |= writeRecovery << 9;

    // Prechard PD
    value |= prechardPd << 12;

    reg_write_32(DdrDevice, DdrOverrideAddress, composeDdrAddress(0, value));
    override_command(DdrCommands::ModeRegisterSet);
}

void write_mode_reg1(bool dllDisable, uint32_t ods, uint32_t rtt, uint32_t al, bool wl, bool tqds, bool outputEnable) {
    uint32_t value = 0; // Register 1

    // DLL enable
    value |= dllDisable ? 1 : 0;

    // Output drive strength
    value |= (ods&1) << 1;
    value |= (ods&2) << (5-1);

    // ODT resistance
    value |= (rtt&1) << 2;
    value |= (rtt&2) << (6-1);
    value |= (rtt&4) << (9-2);

    // Added latency
    value |= al << 3;

    // Write leveling
    value |= wl ? 1<<7 : 0;

    // TQDS termination
    value |= tqds ? 1<<11 : 0;

    // Output enable
    value |= outputEnable ? 0 : 1<<12;

    reg_write_32( DdrDevice, DdrOverrideAddress, composeDdrAddress(1, value) );
    override_command(DdrCommands::ModeRegisterSet);
}

void write_mode_reg2(uint32_t casWriteLatency, bool autoSelfRefresh, uint32_t selfRefreshTemperature, uint32_t rtt) {
    uint32_t value = 0; // Register 2

    // CAS write latency
    value |= casWriteLatency<<3;

    // Auto self refresh
    value |= autoSelfRefresh ? 1<<6 : 0;

    // Self refresh temperature
    value |= selfRefreshTemperature << 7;

    // Dynamic ODT RTT(WR)
    value |= rtt << 9;

    reg_write_32( DdrDevice, DdrOverrideAddress, composeDdrAddress(2, value) );
    override_command(DdrCommands::ModeRegisterSet);
}

void write_mode_reg3(uint32_t mpr_rf, bool mprEnable) {
    uint32_t value = 0; // Register 3

    // MPR read function
    value |= mpr_rf;

    // MPR enable
    value |= mprEnable ? 1<<2 : 0;

    reg_write_32( DdrDevice, DdrOverrideAddress, composeDdrAddress(3, value) );
    override_command(DdrCommands::ModeRegisterSet);
}
}

void ddr_init() {
#if 0
    // Reset EVERYTHING
    ddr_control(DdrCtrl_ResetAll);
    override_command(DdrCommands::NoOperation);         // Set CKE low

    sleep_ns(200'000);

    // Take the DDR out of reset
    ddr_control(DdrCtrl_nMemReset);

    sleep_ns(500'000);

    // Take the DDR PHY out of reset
    ddr_control(DdrCtrl_nMemReset|DdrCtrl_nPhyReset);
    // Set clock enable.
    ddr_control(DdrCtrl_nMemReset|DdrCtrl_nPhyReset|DdrCtrl_Cke); // CKE will take effect at next override command
    override_command(DdrCommands::NoOperation);

    sleep_ns(360);      // tXPR = tRFC (350ns) + 10ns

    write_mode_reg2(
            0,          // CAS write latency 5
            false,      // Manual refersh
            0,          // Normal self refresh temperature
            0           // Dynamic ODT (rTT) disabled
        );
    sleep_cycles(4);    // tMRD

    write_mode_reg3(
            0,          // Predefined MPR pattern
            false       // Multi Purpose Register read disabled
        );
    sleep_cycles(4);    // tMRD

    // Finish initialization with DLL enabled. We're violating the specs as our clock is too slow, but I'm hoping
    // that'll be okay, as we're not issuing any memory accesses and don't care about memory content yet.
    write_mode_reg1(
            false,      // DLL enabled during init (default)
            1,          // Out drive stength 34Ohm (default)
            1,          // RTT 60ohm (default)
            0,          // Additive latency disabled (we have enough latency already)
            false,      // Write leveling disabled
            false,      // TDQS disabled (and irrelevant for our x16 chip)
            true        // Output enabled
        );
    sleep_cycles(4);    // tMRD

    write_mode_reg0(
            0,          // Burst length fixed BL8
            2,          // CAS latency 5
            0,          // Burst type sequential
            true,       // Reset the DLL for the init process (default)
            1,          // Write recovery 5 (tWR=15ns, tCK=10ns at 100MHz. tWR/tCK=1.5. 5 is minimal allowed value.
            0           // Precharge PD DLL off
        );

    sleep_cycles(12);   // tMOD

    reg_write_32( DdrDevice, DdrOverrideAddress, 1<<10 ); // Select long calibration
    override_command(DdrCommands::Calibrate);

    sleep_cycles(512);  // tZQinit

    // Start write leveling
    write_mode_reg1(
            false,      // DLL enabled during init (default)
            1,          // Out drive stength 34Ohm (default)
            1,          // RTT 60ohm (default)
            0,          // Additive latency disabled (we have enough latency already)
            true,       // Write leveling enabled
            false,      // TDQS disabled (and irrelevant for our x16 chip)
            true        // Output enabled
        );
    sleep_cycles(12+24);   // tMOD + tWLDQSEN
    ddr_control(DdrCtrl_nMemReset|DdrCtrl_nPhyReset|DdrCtrl_Cke|DdrCtrl_OutDqs|DdrCtrl_Odt);
    sleep_cycles(40);      // tWLDMRD

    ddr_control(DdrCtrl_nMemReset|DdrCtrl_nPhyReset|DdrCtrl_Cke|DdrCtrl_OutDqs|DdrCtrl_WriteLevel|DdrCtrl_Odt);

    sleep_cycles(1000);

    ddr_control(DdrCtrl_nMemReset|DdrCtrl_nPhyReset|DdrCtrl_Cke);

    // Disable write leveling
    write_mode_reg1(
            false,      // DLL enabled during init (default)
            1,          // Out drive stength 34Ohm (default)
            1,          // RTT 60ohm (default)
            0,          // Additive latency disabled (we have enough latency already)
            false,      // Write leveling disabled
            false,      // TDQS disabled (and irrelevant for our x16 chip)
            true        // Output enabled
        );
    sleep_cycles(4);   // tMRD
    //reg_write_32(DdrDevice, DdrIncDelay, 0x1); // Increase the write delay by once more

    // Enable MPR mode for calibrating the reads
    write_mode_reg3( 0, true );
    sleep_cycles(12);   // tMOD

    reg_write_32(DdrDevice, DdrOverrideAddress, 0);

    int limit = (read_gpio(0)&1) ? 1000 : 2; // Shorter iteration if in simulation
    for( int i=0; i<limit; ++i ) {
        if( reg_read_32(DdrDevice, DdrReadOp)!=0xffff0000 ) {
            uart_send("Increase read delay\n");
            reg_write_32(DdrDevice, DdrIncDelay, 0x2);
        }
    }

    write_mode_reg3( 0, false );
    sleep_cycles(12);   // tMOD
    ddr_control(DdrCtrl_nMemReset|DdrCtrl_nPhyReset|DdrCtrl_Cke|DdrCtrl_nBypass);
#endif
}

