#pragma once

#include <saros/fs/partition.h>

class FAT {
    const Partition &_partition;
public:
    FAT(const Partition &partition);

    FAT(const FAT &that) = delete;
    FAT &operator=(const FAT &that) = delete;
};
