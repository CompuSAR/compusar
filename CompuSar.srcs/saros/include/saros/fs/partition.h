#pragma once

#include "sd.h"

#include <array>
#include <cstdint>
#include <optional>

class PartitionTable {
public:
    static constexpr size_t MaxPartitions = 16;         // About 14 more than what would actually ever be needed

    enum class FsType : uint8_t {
        Unused = 0x00,
        Extended = 0x05,

        Fat12 = 0x01,
        Fat16 = 0x04,
        Fat32 = 0x0b,
        Fat32Lba = 0x0c,
    };

    struct PartitionLine {
        struct CHS {
            uint8_t data[3];

            uint8_t getHead() const { return data[0]; }
            uint8_t getSect() const { return data[1] & ((1<<6) - 1); }
            uint8_t getCyl() const { return (data[1]<<2) | (data[2]>>6); }
        };

        uint8_t boot;
        CHS start;
        FsType fsType = FsType::Unused;
        CHS end;

        uint32_t offset = 0;
        uint32_t size = 0;
    };
    static_assert(sizeof(PartitionLine)==16);

private:
    const SD &sd_;
    std::array<PartitionLine, MaxPartitions> partitions_;
    size_t maxPartition_ = 0;

public:
    PartitionTable(const SD &sd, size_t partitionTableBlock);

    PartitionTable(const PartitionTable &) = delete;
    PartitionTable &operator=(const PartitionTable &) = delete;

    size_t size() const { return maxPartition_; }
    [[nodiscard]] bool empty() { return size()==0; }

    const PartitionLine &at(size_t index) const;
};

class Partition {
    const SD &sd_;
    size_t offset_ = 0;
    size_t size_ = 0;

public:
    Partition(const SD &sd, size_t offset, size_t size);
    Partition(const SD &sd, const PartitionTable::PartitionLine &line) : Partition(sd, line.offset, line.size)
    {}

    SD::BlockPtr readBlock(size_t blockNum) const;
};

extern std::optional<PartitionTable> partitionTable;
