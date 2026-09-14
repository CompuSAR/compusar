#include "apple2_disk.hh"

#include <saros/saros.h>
#include <reg.h>

#include <apple2.h>
#include <apple2_pager.hh>

#include <uart.h>
#include <format.h>

#include <mutex>

#include <6502_dbg.hh>

using namespace Apple2;

static constexpr uint32_t DeviceNum = 0x82;

static constexpr uint32_t TrackDataAddr = 0x0000;
static constexpr uint32_t TrackLengthBits = 0x0004;
static constexpr uint32_t TrackPositionBits = 0x0008;
static constexpr uint32_t MotorSpinRatio = 0x000c;
static constexpr uint32_t MotorControl = 0x0010;
    static constexpr uint32_t MotorControl__MotorOn = 0x01;
    static constexpr uint32_t MotorControl__ResetFreqDiv = 0x02;
static constexpr uint32_t DataMemValid = 0x0014;

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

void Diskette::eject() {
    std::unique_lock loadLocker(loadLock);

    ejectImpl();
}

void Diskette::reset() {
    motorOn = false;

    updateDiskHw(true);
}

static void debugThread0(void *) noexcept {
    while(true) {
        dbg6502Bp[1].wait();

        uart_send("DBG: B0 ReadSector T:");
        print_dec( *translateAddr(0x41, false) );
        uart_send(" S:");
        print_hex( *translateAddr(0x3d, false) );
        uart_send(" -> $");
        uint16_t dstAddr = *translateAddr(0x27, false);
        dstAddr <<= 8;
        dstAddr |= *translateAddr(0x26, false);
        print_hex( dstAddr );
        uart_send("\n");

        // Set the breakpoint to the sector successfully read point
        set_breakpoint(1, 0xc6eb, BP_SYNC, BP_SYNC);
        dbg6502Bp[1].clear();
        dbg_cont();

        dbg6502Bp[1].wait();
        uart_send("DBG: B0 ReadSector success:\n");
        for(unsigned j=0; j<16; ++j) {
            for(unsigned i=0; i<16; ++i) {
                uart_send(" ");
                if( i==8 )
                    uart_send(" ");
                print_hex( *translateAddr(dstAddr, false) );
                dstAddr++;
            }
            uart_send("\n");
        }

        uart_send("\n");
        set_breakpoint(1, 0xc65c, BP_SYNC, BP_SYNC);
        dbg6502Bp[1].clear();
        dbg_cont();
    }
}

static void debugThreadRwts(void *) noexcept {
    while(true) {
        dbg6502Bp[2].wait();

        uint16_t iocb = dbg_readReg(DbgReg::A);
        iocb <<= 8;
        iocb |= dbg_readReg(DbgReg::Y);

        uart_send("DBG: RWTS Op ");
        print_hex( *translateAddr(iocb+0xc, false) );
        uart_send(" T:");
        print_hex( *translateAddr(iocb+0x4, false) );
        uart_send(" S:");
        print_hex( *translateAddr(iocb+0x5, false) );
        uart_send(" -> $");
        uint16_t dstAddr = *translateAddr(iocb+0x9, false);
        dstAddr <<= 8;
        dstAddr |= *translateAddr(iocb+0x8, false);
        print_hex( dstAddr );

        uint8_t sp = dbg_readReg(DbgReg::S);
        sp++;
        uint16_t retAddr = *translateAddr(0x100+sp, false);
        sp++;
        retAddr |= (*translateAddr(0x100+sp, false)) << 8;
        retAddr++;

        uart_send(" return to $");
        print_hex(retAddr);
        uart_send("\n");

        // Set the breakpoint to the sector successfully read point
        set_breakpoint(2, retAddr, BP_SYNC, BP_SYNC);
        dbg6502Bp[2].clear();
        dbg_cont();

        dbg6502Bp[2].wait();
        uart_send("DBG: RWTS ReadSector returned ");
        if( dbg_readReg(DbgReg::P) & 0x01 ) {
            uart_send("failure ");
            print_hex( *translateAddr(iocb + 0xd, false) );
            uart_send("\n");
        } else {
            uart_send("success\n");
        }
        for(unsigned j=0; j<16; ++j) {
            for(unsigned i=0; i<16; ++i) {
                uart_send(" ");
                if( i==8 )
                    uart_send(" ");
                print_hex( *translateAddr(dstAddr, false) );
                dstAddr++;
            }
            uart_send("\n");
        }

        uart_send("\n");
        set_breakpoint(2, 0xb7b5, BP_SYNC, BP_SYNC);
        dbg6502Bp[2].clear();
        dbg_cont();
    }
}

bool Diskette::load(Filesystem::File &image) {
#ifdef DEBUG
    set_breakpoint(1, 0xc65c, BP_SYNC, BP_SYNC);
    saros.createThread(debugThread0, nullptr, "DISK debug thread B0"_fs);
    set_breakpoint(2, 0xb7b5, BP_SYNC, BP_SYNC);
    saros.createThread(debugThreadRwts, nullptr, "DISK debug thread RWTS"_fs);
#endif

    // We are, essentially, formatting the floppy here.
    static constexpr size_t Gap1Size = 128;     // Beginning of track gap to be overwritten by last sector
    static constexpr size_t Gap2Size = 5;       // Between sector header and data
    static constexpr size_t Gap3Size = 16;      // Before regular sector header. Officially between 14 and 24.
    // The above number needs to be tuned to the drive's speed to prevent the overflow/underflow assert from triggering.
    static constexpr size_t SectorsPerTrack = 16;

    static constexpr size_t SectorSize = 256;

    SD::BlockPtr blockData;
    size_t blockSize = 0;

    std::unique_lock locker(loadLock);
    ejectImpl();

    for( uint8_t track = 0; track <= MaxTrack; ++track ) {
        std::array<SD::BlockPtr, SectorsPerTrack/2> trackBlocks;
        std::array<std::span<uint8_t>, SectorsPerTrack> trackData;

        for( unsigned i=0; i<trackBlocks.size(); ++i ) {
            size_t blockSize = image.readBlock(trackBlocks[i]);

            if( blockSize!=SD::BlockSize ) {
                uart_send("E: Failed to read source DSK\n");

                return false;
            }

            trackData[i*2] = std::span<uint8_t, SectorSize>( &trackBlocks[i]->data[0], SectorSize );
            trackData[i*2+1] = std::span<uint8_t, SectorSize>( &trackBlocks[i]->data[SectorSize], SectorSize );
        }

        static constexpr unsigned DosInterleaving[] = {
            0x0, 0x7, 0xe, 0x6, 0xd, 0x5, 0xc, 0x4, 0xb, 0x3, 0xa, 0x2, 0x9, 0x1, 0x8, 0xf
        };
        static_assert(sizeof(DosInterleaving)/sizeof(DosInterleaving[0]) == SectorsPerTrack);

        uint32_t position = 0;

        uint32_t dataStartPos = 0;

        for( unsigned sector = 0; sector < 16; ++sector ) {
#ifdef DEBUG
            uart_send("D: Writing bit pattern for track ");
            print_dec(track);
            uart_send(" sector ");
            print_hex(sector);
            uart_send("\n");

            const uint8_t *dbg_trk_data = trackData[ DosInterleaving[sector] ].data();
            for(unsigned j=0; j<16; ++j) {
                for(unsigned i=0; i<16; ++i) {
                    uart_send(" ");
                    if( i==8 )
                        uart_send(" ");

                    print_hex(dbg_trk_data[j*16+i]);
                }

                uart_send("\n");
            }
#endif

            // Write the sector header
            for( unsigned i=0; i<(sector==0 ? Gap1Size : Gap3Size); ++i )
                trackWriteSelfSync(track, position);

            if( sector==0 )
                dataStartPos = position;

            trackWriteByte(track, position, 0xD5);
            trackWriteByte(track, position, 0xAA);
            trackWriteByte(track, position, 0x96);

            uint8_t checksum = 0;
            constexpr uint8_t VolumeId = 254;
            trackWriteData44(track, position, VolumeId, &checksum);
            trackWriteData44(track, position, track, &checksum);
            trackWriteData44(track, position, sector, &checksum);
            trackWriteData44(track, position, checksum);

            trackWriteByte(track, position, 0xDE);
            trackWriteByte(track, position, 0xAA);
            trackWriteByte(track, position, 0xEB);


            // Write the sector data
            for( unsigned i=0; i<Gap2Size; ++i )
                trackWriteSelfSync(track, position);

            trackWriteByte(track, position, 0xD5);
            trackWriteByte(track, position, 0xAA);
            trackWriteByte(track, position, 0xAD);

            trackWriteSector62(track, position, trackData[ DosInterleaving[sector] ] );

            trackWriteByte(track, position, 0xDE);
            trackWriteByte(track, position, 0xAA);
            trackWriteByte(track, position, 0xEB);

#ifdef DEBUG
            uart_send("D: End of sector track position: ");
            print_dec(position);
            uart_send("\n");
#endif
        }

#ifdef DEBUG
        uart_send("D: Gap 1 ends at ");
        print_dec(dataStartPos);
        uart_send("\n");
#endif
        assertWithMessage( dataStartPos > position, "Track data was too long (overflow) or too short (underflow)" );
    }

    diskDataValid = true;

    std::unique_lock stateLocker(lock);
    updateTrackData(0);
    updateDiskHw(false);

    return true;
}

void Diskette::debugDump() const {
    uart_send("Current state of dma data: 0: ");
    print_hex(reg_read_32(DeviceNum, 0x8000));
    uart_send(" ");
    print_hex(reg_read_32(DeviceNum, 0x8004));
    uart_send(" ");
    print_hex(reg_read_32(DeviceNum, 0x8008));
    uart_send(" ");
    print_hex(reg_read_32(DeviceNum, 0x800c));
    uart_send("   1: ");
    print_hex(reg_read_32(DeviceNum, 0x8010));
    uart_send(" ");
    print_hex(reg_read_32(DeviceNum, 0x8014));
    uart_send(" ");
    print_hex(reg_read_32(DeviceNum, 0x8018));
    uart_send(" ");
    print_hex(reg_read_32(DeviceNum, 0x801c));
    uart_send("\n");

    uart_send("Status: ");
    print_hex(reg_read_32(DeviceNum, 0x8100));
    uart_send("\nTrack start: ");
    print_hex(reg_read_32(DeviceNum, 0x8104));
    uart_send("\nTrack pos: ");
    print_hex(reg_read_32(DeviceNum, 0x8108));
    uart_send("\nLast fecth: ");
    print_hex(reg_read_32(DeviceNum, 0x810c));
    uart_send("\nApple cycles: ");
    print_hex(reg_read_32(DeviceNum, 0x8110));
    uart_send("\n");
}

void Diskette::ioHandleThread() noexcept {
    uart_send("Apple DiskII emulation thread started\n");

    while( true ) {
        reqPending.wait();

        std::unique_lock stateLocker(lock);

#ifdef DEBUG
        uart_send("DSK ");
        print_hex(pendingAddr);
        if( pendingWrite ) {
            uart_send(" W:");
            print_hex(pendingData);
        } else {
            uart_send(" R");
        }
        uart_send("\n");
#endif

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
                uart_send("Drive motor off\n");
                break;
            case SOFTSW_MOTORON:
                motorOn = true;
                uart_send("Drive motor on\n");
                break;
            case SOFTSW_DRV0EN:
                driveOn = true;
                uart_send("Drive 0 selected\n");
                break;
            case SOFTSW_DRV1EN:
                driveOn = false;
                uart_send("Drive 1 selected\n");
                break;
            case SOFTSW_Q7L:
                writeMode = false;
                uart_send("Drive read mode selected\n");
                break;
            default:
                abortWithMessage("Unimplemented");
            }
        }

        updateDiskHw(false);

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

#ifdef DEBUG
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
            assertWithMessage(currentTrackX4==MaxExpandedTrack, "Track position should have been different");
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

    if( currentTrackX4 > MaxExpandedTrack )
        currentTrackX4 = MaxExpandedTrack;

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

void Diskette::ejectImpl() {
    // Must be called with loadLock already acquired
    std::unique_lock stateLocker(lock);

    diskDataValid = false;

    updateDiskHw(true);
}

void Diskette::trackWriteBit(uint8_t track, uint32_t &position, bool bit) {
    // This assumes little endian
    const uint32_t bytePosition = position / 8;
    const uint32_t bitPosition = position % 8;

    if( bit )
        rawDiskImage[track][bytePosition] |= 1<<bitPosition;
    else
        rawDiskImage[track][bytePosition] &= ~(1<<bitPosition);

    if( ++position >= TrackSizeBits ) {
        position = 0;
    }
}

void Diskette::trackWriteByte(uint8_t track, uint32_t &position, uint8_t data) {
    uint8_t mask = 0x80;

    while( mask!=0 ) {
        trackWriteBit(track, position, (data&mask) != 0);
        mask >>= 1;
    }
}

void Diskette::trackWriteSelfSync(uint32_t track, uint32_t &position) {
    trackWriteBit(track, position, true);
    trackWriteBit(track, position, true);
    trackWriteBit(track, position, true);
    trackWriteBit(track, position, true);
    trackWriteBit(track, position, true);
    trackWriteBit(track, position, true);
    trackWriteBit(track, position, true);
    trackWriteBit(track, position, true);
    trackWriteBit(track, position, false);
    trackWriteBit(track, position, false);
}

void Diskette::trackWriteData44(uint8_t track, uint32_t &position, uint8_t data, uint8_t *checksum) {
    if( checksum!=nullptr )
        *checksum ^= data;

    trackWriteByte( track, position, (data>>1) | 0xaa );
    trackWriteByte( track, position, data | 0xaa );
}

/**
 * This code implements "6 and 2" encoding of a sector. See chapter 3 of "Beneath Apple DOS" for
 * details.
 */
void Diskette::trackWriteSector62(uint8_t track, uint32_t &position, std::span<uint8_t> data) {
    static constexpr uint8_t TranslationTable[] = {
        0x96, 0x97, 0x9a, 0x9b, 0x9d, 0x9e, 0x9f, 0xa6,
        0xa7, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb2, 0xb3,
        0xb4, 0xb5, 0xb6, 0xb7, 0xb9, 0xba, 0xbb, 0xbc,
        0xbd, 0xbe, 0xbf, 0xcb, 0xcd, 0xce, 0xcf, 0xd3,
        0xd6, 0xd7, 0xd9, 0xda, 0xdb, 0xdc, 0xdd, 0xde,
        0xdf, 0xe5, 0xe6, 0xe7, 0xe9, 0xea, 0xeb, 0xec,
        0xed, 0xee, 0xef, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6,
        0xf7, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff,
    };
    static_assert( sizeof(TranslationTable) == 64 );
#define NAIVE_AUX 0

#if !NAIVE_AUX
    // The "2" bits are reversed (LSB high). Rather than perform expensive bit manipulations,
    // when we store them, we use a table that transposes the encoded values.
    static constexpr uint8_t TranslationTableAux[] = {
        0x96, 0x9a, 0x97, 0x9b, 0xa7, 0xac, 0xab, 0xad,
        0x9d, 0x9f, 0x9e, 0xa6, 0xae, 0xb2, 0xaf, 0xb3,
        0xd6, 0xd9, 0xd7, 0xda, 0xdf, 0xe6, 0xe5, 0xe7,
        0xdb, 0xdd, 0xdc, 0xde, 0xe9, 0xeb, 0xea, 0xec,
        0xb4, 0xb6, 0xb5, 0xb7, 0xbd, 0xbf, 0xbe, 0xcb,
        0xb9, 0xbb, 0xba, 0xbc, 0xcd, 0xcf, 0xce, 0xd3,
        0xed, 0xef, 0xee, 0xf2, 0xf7, 0xfa, 0xf9, 0xfb,
        0xf3, 0xf5, 0xf4, 0xf6, 0xfc, 0xfe, 0xfd, 0xff,
    };
    static_assert( sizeof(TranslationTableAux) == 64 );
#endif

    std::array<uint8_t, (SectorSize + 2)/3> auxBuffer;

    for(auto &byte : auxBuffer)
        byte = 0;

    assertWithMessage(data.size() == SectorSize, "trackWriteSector62 called with invalid sector size");

    unsigned auxPos = 0, auxShift = 0;

    for(uint8_t byte : data) {
#if NAIVE_AUX
        uint8_t bitSwitched;

        switch(byte&0x03) {
        case 0x00:
        case 0x03:
            bitSwitched = byte&0x03;
            break;
        case 0x01:
            bitSwitched = 0x02;
            break;
        case 0x02:
            bitSwitched = 0x01;
            break;
        }

        auxBuffer[auxPos++] |= bitSwitched << auxShift;
#else
        auxBuffer[auxPos++] |= (byte&0x03) << auxShift;
#endif

        if( auxPos == auxBuffer.size() ) {
            auxPos = 0;
            auxShift += 2;
        }
    }

    uint8_t prevByte = 0;
    // Write the "2"
    for(uint8_t byte : auxBuffer) {
        assertWithMessage((byte&0xc0) == 0, "Aux buffer byte must have two zero MSb");
#if NAIVE_AUX
        uint8_t convertedByte = TranslationTable[byte ^ prevByte];
#else
        uint8_t convertedByte = TranslationTableAux[byte ^ prevByte];
#endif
        trackWriteByte(track, position, convertedByte);

        prevByte = byte;
    }

#if !NAIVE_AUX
    // The transposed table covered the actual bytes written. Before we move to the 6 bits, we need to transpose the
    // checksum, or the end checksum will be wrong.
    {
        uint8_t newChecksum = 0;

        if( (prevByte&0x01) )
            newChecksum |= 0x02;
        if( (prevByte&0x02) )
            newChecksum |= 0x01;
        if( (prevByte&0x04) )
            newChecksum |= 0x08;
        if( (prevByte&0x08) )
            newChecksum |= 0x04;
        if( (prevByte&0x10) )
            newChecksum |= 0x20;
        if( (prevByte&0x20) )
            newChecksum |= 0x10;

        prevByte = newChecksum;
    }
#endif

    // Write the "6"
    for(uint8_t byte : data) {
        byte >>= 2;
        uint8_t convertedByte = TranslationTable[byte ^ prevByte];
        trackWriteByte(track, position, convertedByte);

        prevByte = byte;
    }

    // Write the checksum
    trackWriteByte(track, position, TranslationTable[prevByte]);
}

// Sync the hardware to our soft state. Must be called with lock held
void Diskette::updateDiskHw(bool force) {
    if( lhwsForceNextTime ) {
        force = true;
        lhwsForceNextTime = false;
    }

    uint32_t driveMotorValue = 0;

    const bool motorState = motorOn && driveOn;
    if( motorState )
        driveMotorValue |= MotorControl__MotorOn;

    reg_write_32(DeviceNum, MotorControl, driveMotorValue | MotorControl__ResetFreqDiv);

    if( currentTrackX4!=lhwsTrack || force ) {
        if( diskDataValid )
            updateTrackData( reg_read_32(DeviceNum, TrackPositionBits) );
        else
            reg_write_32(DeviceNum, DataMemValid, 0);

        lhwsTrack = currentTrackX4;
    }

    reg_write_32(DeviceNum, MotorSpinRatio, 3<<16 | 1);
    reg_write_32(DeviceNum, MotorControl, driveMotorValue);
}

void Diskette::updateTrackData(uint32_t trackPos) {
    reg_write_32(DeviceNum, DataMemValid, 0);

    if( currentTrackX4 % 4 == 0 ) {
        reg_write_32(DeviceNum, TrackDataAddr, reinterpret_cast<uint32_t>(rawDiskImage[currentTrackX4/4].data()));
        reg_write_32(DeviceNum, TrackLengthBits, TrackSizeBits);
        reg_write_32(DeviceNum, TrackPositionBits, trackPos);
        reg_write_32(DeviceNum, DataMemValid, 1);
    }
}
