#pragma once

#include <saros/fs/fat.h>

#include <optional>

using Filesystem = FAT;

extern std::optional<Filesystem> fs;
// XXX This is not even a little thread safe
extern Saros::Sync::Signal fsChanged;
