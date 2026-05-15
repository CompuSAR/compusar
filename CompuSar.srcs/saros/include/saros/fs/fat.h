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
    FAT(const Partition &partition);

    FAT(const FAT &that) = delete;
    FAT &operator=(const FAT &that) = delete;

    SD::BlockPtr readCluster(uint32_t clusterNum) const;
    uint32_t nextCluster(uint32_t clusterNum) const;
};
