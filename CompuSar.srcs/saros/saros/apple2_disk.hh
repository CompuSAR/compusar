#pragma once

#include <saros/fs/filesystem.h>
#include <saros/sync/event.h>

#include <hw-params.h>

#include <array>
#include <cstdint>

class Diskette {
    static constexpr uint16_t MaxTrack = 34;
    static constexpr uint16_t MaxExpandedTrack = MaxTrack * 4 + 1;
    static constexpr size_t TrackSizeBits = 50'000;
    static constexpr size_t TrackStorageSize =
            (TrackSizeBits - (TrackSizeBits + CACHELINE_SIZE_BITS - 1) % CACHELINE_SIZE_BITS + CACHELINE_SIZE_BITS) / 8;
    static_assert( (TrackStorageSize % CACHELINE_SIZE_BYTES) == 0, "Track storage size isn't bound to cacheline size" );
    static_assert( TrackStorageSize*8 >= TrackSizeBits );
    static constexpr size_t SectorSize = 256;

    Saros::Sync::Event reqPending;
    Saros::Sync::Mutex lock;

    // Raw disk buffer
    std::array< std::array< uint8_t, TrackStorageSize >, MaxTrack + 1 > __attribute__((aligned(16))) rawDiskImage;

    // pending I/O request
    uint16_t pendingAddr;
    uint8_t pendingData;
    bool pendingWrite;

    bool writeMode = false;
    bool driveOn = true;
    bool motorOn = false;
    bool diskDataValid = false;

    bool stepMotorPhase[4] = {};
    uint16_t currentTrackX4 = 17*4;       // Times 4

    // Last HW state
    bool lhwsForceNextTime = true;
    bool lhwsMotor = false;
    bool lhwsValidDisk = false;
    uint16_t lhwsTrack = 0;

public:
    Diskette();
    Diskette( const Diskette &that ) = delete;
    Diskette &operator=( const Diskette &that ) = delete;

    bool handleIo(uint16_t addr, bool write, uint8_t data, bool pending);

    void eject();
    void reset();
    bool load(Filesystem::File &image);

private:
    void ioHandleThread() noexcept;
    void calcNewTrack( uint8_t phase, bool on );

    void trackWriteBit(uint8_t track, uint32_t &position, bool bit);
    void trackWriteByte(uint8_t track, uint32_t &position, uint8_t data);
    void trackWriteSelfSync(uint32_t track, uint32_t &position);
    void trackWriteData44(uint8_t track, uint32_t &position, uint8_t data, uint8_t *checksum = nullptr);
    void trackWriteSector62(uint8_t track, uint32_t &position, std::span<uint8_t> data);

    void updateDiskHw(bool force);
    void updateTrackData(uint32_t trackPos);
};
