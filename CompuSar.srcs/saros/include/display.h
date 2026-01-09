#pragma once

#include "bitmap.h"

#include <saros/sync/signal.h>

namespace Display {

extern Saros::Sync::Signal vsyncSignal;

void setDisplay(const Bitmap &sprite, uint16_t originX, uint16_t originY);

void handle_vsync_irq();

static constexpr uint32_t DeviceId = 5;
} // namespace Display
