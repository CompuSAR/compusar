#include "apple2_disk.hh"

#include <saros/saros.h>
#include <reg.h>

#include <apple2.h>

#include <uart.h>
#include <format.h>

static constexpr uint32_t DeviceNum = 0x82;

static constexpr uint32_t TrackDataAddr = 0x0000;
static constexpr uint32_t TrackLengthBits = 0x0004;
static constexpr uint32_t TrackPositionBits = 0x0008;
static constexpr uint32_t MotorSpinRatio = 0x000c;
static constexpr uint32_t MotorControl = 0x0010;
    static constexpr uint32_t MotorControl__MotorOn = 0x01;
    static constexpr uint32_t MotorControl__ResetFreqDiv = 0x02;

static constexpr uint8_t SOFTSW_PHASE0OFF =     0x0;
static constexpr uint8_t SOFTSW_PHASE0ON =      0x1;
static constexpr uint8_t SOFTSW_PHASE1OFF =     0x2;
static constexpr uint8_t SOFTSW_PHASE1ON =      0x3;
static constexpr uint8_t SOFTSW_PHASE2OFF =     0x4;
static constexpr uint8_t SOFTSW_PHASE2ON =      0x5;
static constexpr uint8_t SOFTSW_PHASE3OFF =     0x6;
static constexpr uint8_t SOFTSW_PHASE3ON =      0x7;
static constexpr uint8_t SOFTSW_MOTOROFF =      0x8;
static constexpr uint8_t SOFTSW_MOTORON =       0x9;
static constexpr uint8_t SOFTSW_DRV0EN =        0xa;
static constexpr uint8_t SOFTSW_DRV1EN =        0xb;
static constexpr uint8_t SOFTSW_Q6L =           0xc;
static constexpr uint8_t SOFTSW_Q6H =           0xd;
static constexpr uint8_t SOFTSW_Q7L =           0xe;
static constexpr uint8_t SOFTSW_Q7H =           0xf;

using namespace Saros;

Diskette::Diskette() {
    saros.createThread(
            [](void *object) noexcept { reinterpret_cast<Diskette *>(object)->ioHandleThread(); },
            this,
            "Disk IO handler"_fs,
            true);
}

bool Diskette::handleIo(uint16_t addr, bool write, uint8_t data, bool pending) {
    if( pending ) {
        pendingAddr = addr;
        pendingData = data;
        pendingWrite = write;

        reqPending.set();
        saros.disableSoftwareInterrupt();
    }

    return false;
}

void Diskette::eject() {}
void Diskette::load(Filesystem::File &image) {}

void Diskette::ioHandleThread() noexcept {
    uart_send("Apple DiskII emulation thread started\n");

    while( true ) {
        reqPending.wait();

        uart_send("DSK ");
        print_hex(pendingAddr);
        if( pendingWrite ) {
            uart_send(" W:");
            print_hex(pendingData);
        } else {
            uart_send(" R");
        }
        uart_send("\n");

        uint8_t result = 0;
        if( pendingWrite ) {
            abortWithMessage("Unimplemented");
        } else {
            switch( pendingAddr & 0x0f ) {
            case SOFTSW_PHASE0OFF:
            case SOFTSW_PHASE0ON:
            case SOFTSW_PHASE1OFF:
            case SOFTSW_PHASE1ON:
            case SOFTSW_PHASE2OFF:
            case SOFTSW_PHASE2ON:
            case SOFTSW_PHASE3OFF:
            case SOFTSW_PHASE3ON:
                calcNewTrack( (pendingAddr & 0x06)>>1, (pendingAddr & 0x01) == 1 );
                break;
            case SOFTSW_MOTOROFF:
                motorOn = false;
                break;
            case SOFTSW_MOTORON:
                motorOn = true;
                break;
            case SOFTSW_DRV0EN:
                driveOn = true;
                break;
            case SOFTSW_DRV1EN:
                driveOn = false;
                break;
            case SOFTSW_Q7L:
                writeMode = false;
                break;
            default:
                abortWithMessage("Unimplemented");
            }
        }

        reg_write_32( Apple2::IoDeviceNum, Apple2::Io_Event, result );

        reqPending.clear();
        saros.enableSoftwareInterrupt();
    }
}

void Diskette::calcNewTrack( uint8_t phase, bool on ) {
    if( stepMotorPhase[phase] == on )
        return;

    uint8_t currentPhase = (currentTrackX4 & 0x06)>>1;
    bool halfPhase = currentTrackX4 & 0x01;
    uint8_t phaseDiff = (phase + 4 - currentPhase) % 4;
    bool currentPhaseOn = stepMotorPhase[currentPhase];

#if DEBUG
    uart_send("DBG: currentPhase ");
    print_dec(currentPhase);
    if( halfPhase )
        uart_send(" half");
    uart_send( currentPhaseOn ? " V" : " X" );
    uart_send(" new phase ");
    print_dec(phase);
    uart_send( on ? " V" : " X" );
    uart_send(" diff ");
    print_dec( phaseDiff );
    uart_send(" Track ");
    print_dec(currentTrackX4);
    uart_send("\n");
#endif

    bool trackChanged = false;

    if( on && currentPhaseOn ) {
        if( !halfPhase ) {
            switch( phaseDiff ) {
            case 0:
                abortWithMessage("No change in phase should have been caught by earlier ifs");
                break;
            case 1:
                assertWithMessage( !halfPhase, "Current phase was on, next off, but we were on quarter track");
                currentTrackX4 += 1;
                trackChanged = true;
                break;
            case 3:
                if( !halfPhase ) {
                    currentTrackX4 -= 1;
                    trackChanged = true;
                } else {
                    uart_send("While we're on quarter track with next prev was turned on\n");
                    // Do nothing
                }
                break;
            case 2:
                // Phase turned on is on the other side of the current loop. Ignore
                break;
            default:
                abortWithMessage("Unreachable");
            }
        } else {
            // Turned on phase can't affect head on quarter track, as it's already between two on magnets
        }
    } else if( on && !currentPhaseOn ) {
        assertWithMessage( !halfPhase, "If current phase is off than we can't be on quarter track" );

        switch( phaseDiff ) {
        case 0:
            // Just turned on for the track we're already on
            break;
        case 1:
            currentTrackX4 += 2;
            trackChanged = true;
            break;
        case 3:
            currentTrackX4 -= 2;
            trackChanged = true;
            break;
        case 2:
            // Too far. Let's assume we don't move, though it's sketchy
            uart_send("Attempt to move whole track at once. Direction unclear.\n");
            break;
        default:
            abortWithMessage("Unreachable");
        }
    } else if( !on && currentPhaseOn ) {
        switch( phaseDiff ) {
        case 0:
            // Turning off the current phase
            if( halfPhase ) {
                assertWithMessage( stepMotorPhase[currentPhase+1], "Half phase set but relevant phase isn't turned on" );
                currentTrackX4 += 1;
                trackChanged = true;
            } else {
                // No movement. We're just not held
            }
            break;
        case 1:
            assertWithMessage( halfPhase, "Both current phase and next phase were on, but half phase was not set" );
            currentTrackX4 -= 1;
            trackChanged = true;
            break;
        case 3:
            assertWithMessage( halfPhase, "Both current phase and prev phase were on, but we are not half phase with next" );
            break;
        case 2:
            // Other side. Don't care
            break;
        default:
            abortWithMessage("Unreachable");
        }
    } else if( !on && !currentPhaseOn ) {
        switch( phaseDiff ) {
        case 0:
            abortWithMessage("No change in phase should have been caught by earlier ifs");
            break;
        case 1:
            assertWithMessage(currentTrackX4==MaxTrack, "Track position should have been different");
        case 3:
            assertWithMessage(currentTrackX4==0, "Track position should have been different");
            break;
        case 2:
            // Don't really care
            break;
        default:
            uart_send("Illegal phase diff ");
            print_dec(phaseDiff);
            uart_send("\n");

            abortWithMessage("Unreachable");
        }
    } else {
        abortWithMessage( "Invalid combination reached" );
    }

    stepMotorPhase[phase] = on;

    bool headBang = false;
    if( currentTrackX4 > 0x8000 ) {
        headBang = true;
        currentTrackX4 = 0;
    }

    if( currentTrackX4 > MaxTrack )
        currentTrackX4 = MaxTrack;

    if( trackChanged ) {
        uart_send("DISK II is on track ");
        print_dec(currentTrackX4 >> 2);
        switch( currentTrackX4 % 4 ) {
        case 0:
            uart_send("\n");
            break;
        case 1:
            uart_send("¼\n");
            break;
        case 2:
            uart_send("½\n");
            break;
        case 3:
            uart_send("¾\n");
            break;
        }
    }
}
