#pragma once

#include <saros/fs/filesystem.h>
#include <saros/sync/event.h>

#include <cstdint>

class Diskette {
    static constexpr uint16_t MaxTrack = 40 * 4;

    Saros::Sync::Event reqPending;

    // pending I/O request
    uint16_t pendingAddr;
    uint8_t pendingData;
    bool pendingWrite;

    bool writeMode = false;
    bool driveOn = true;
    bool motorOn = false;

    bool stepMotorPhase[4] = {};
    uint16_t currentTrackX4 = 17*4;       // Times 4
public:
    Diskette();
    Diskette( const Diskette &that ) = delete;
    Diskette &operator=( const Diskette &that ) = delete;

    bool handleIo(uint16_t addr, bool write, uint8_t data, bool pending);

    void eject();
    void load(Filesystem::File &image);

private:
    void ioHandleThread() noexcept;
    void calcNewTrack( uint8_t phase, bool on );
};
