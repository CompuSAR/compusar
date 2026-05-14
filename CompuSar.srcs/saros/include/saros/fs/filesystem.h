#pragma once

#include <saros/fs/fat.h>

#include <optional>

using Filesystem = FAT;

extern std::optional<Filesystem> fs;
