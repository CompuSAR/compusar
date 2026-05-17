#pragma once

#include <saros/fs/partition.h>

class FAT {
    const Partition &partition_;

    uint32_t totalSectors_ = 0, firstDataSector_ = 0, rootCluster_ = 0;

    static constexpr size_t SECT_PER_CLUSTER = 1;
    static constexpr size_t FIRST_USABLE_CLUSTER = 2;
    static constexpr size_t ROOT_DIR_CLUSTER = FIRST_USABLE_CLUSTER;
    static constexpr size_t CLUSTERS_PER_FAT_SECTOR = SD::BlockSize / sizeof(uint32_t);
public:

    static constexpr uint32_t FREE_CLUSTER = 0x00000000;
    static constexpr uint32_t END_OF_CHAIN = 0x0fffffff;
    static constexpr uint32_t BAD_CLUSTER = 0x0ffffff7;

    FAT(const Partition &partition);

    FAT(const FAT &that) = delete;
    FAT &operator=(const FAT &that) = delete;

    SD::BlockPtr readCluster(uint32_t clusterNum) const;
    uint32_t nextCluster(uint32_t clusterNum) const;
};
