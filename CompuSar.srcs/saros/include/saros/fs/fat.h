#pragma once

#include <saros/fs/partition.h>

class FAT {
    const Partition &partition_;

    uint32_t totalSectors_ = 0, firstDataSector_ = 0, firstFatSector_ = 0;

    static constexpr size_t SECT_PER_CLUSTER = 1;
    static constexpr size_t FIRST_USABLE_CLUSTER = 2;
    static constexpr size_t CLUSTERS_PER_FAT_SECTOR = SD::BlockSize / sizeof(uint32_t);
public:
    struct ClusterNum {
        uint32_t num = 0;

        bool isValid() const {
            return num >= FIRST_USABLE_CLUSTER && !isBad() && !isEoc();
        }
        bool isFree() const {
            return num == 0;
        }
        bool isBad() const {
            return num == 0x0ffffff7;
        }
        bool isEoc() const {
            return num >= 0x0FFFFFF8;
        }
    };
    static constexpr ClusterNum RootDirCluster{FIRST_USABLE_CLUSTER};

    class Directory {
        ClusterNum dirStart_;
        const FAT &fs_;

        explicit Directory(const FAT &fs, ClusterNum dirStart) : dirStart_(dirStart), fs_(fs) {}
        friend FAT;

        struct __attribute__((packed)) DirEntry {
            static constexpr uint8_t AttrReadOnly = 0x01;
            static constexpr uint8_t AttrHidden = 0x02;
            static constexpr uint8_t AttrSystem = 0x04;
            static constexpr uint8_t AttrVolumeId = 0x08;
            static constexpr uint8_t AttrDirectory = 0x10;
            static constexpr uint8_t AttrArchive = 0x20;
            static constexpr uint8_t AttributeLongName = AttrReadOnly | AttrHidden | AttrSystem | AttrVolumeId;
            static constexpr uint8_t FreeMarker = 0xe5;
            static constexpr uint8_t EndMarker = 0x00;

            char dirName[11];
            uint8_t dirAttr;
            uint8_t dirNtRes;
            uint8_t dirCrtTimeTenth;
            uint16_t dirCrtTime;
            uint16_t dirCrtDate;
            uint16_t dirLstAccDate;
            uint16_t dirFstClusHi;
            uint16_t dirWrtTime;
            uint16_t dirWrtDate;
            uint16_t dirFstClusLo;
            uint32_t dirFileSize;
        };
        static_assert(sizeof(DirEntry)==32);
        static_assert(offsetof(DirEntry, dirFileSize)==28);
        static_assert(std::is_standard_layout_v<DirEntry>);
        static_assert(std::is_trivially_copyable_v<DirEntry>);

        static constexpr size_t DirEntriesPerSector = SD::BlockSize / sizeof(DirEntry);
        static_assert( DirEntriesPerSector * sizeof(DirEntry) == SD::BlockSize, "Block size not a multiple of directory entry" );
    public:
        void dir() const;
    };

    FAT(const Partition &partition);

    FAT(const FAT &that) = delete;
    FAT &operator=(const FAT &that) = delete;

    explicit operator bool() const {
        return totalSectors_!=0;
    }

    SD::BlockPtr readCluster(ClusterNum clusterNum) const;
    ClusterNum nextCluster(ClusterNum clusterNum) const;

    Directory getRootDir() const {
        return Directory(*this, RootDirCluster);
    }
};
