static constexpr uint32_t DeviceNum = 0x82;

static constexpr uint32_t TrackDataAddr = 0x0000;
static constexpr uint32_t TrackLengthBits = 0x0004;
static constexpr uint32_t TrackPositionBits = 0x0008;
static constexpr uint32_t MotorSpinRatio = 0x000c;
static constexpr uint32_t MotorControl = 0x0010;
    static constexpr uint32_t MotorControl__MotorOn = 0x01;
    static constexpr uint32_t MotorControl__ResetFreqDiv = 0x02;

void loadDiskTrack(void *trackData, size_t trackSize) {
    reg_write_32(DeviceNum, TrackDataAddr, trackData);
    reg_write_32(DeviceNum, TrackLengthBits, trackSize);
}

void setTrackPosition(size_t position) {
    reg_write_32(DeviceNum, TrackPositionBits, position);
}

void driveOn() {}
void driveOff() {}


