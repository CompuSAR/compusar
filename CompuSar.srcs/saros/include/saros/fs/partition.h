#pragma once

#include <optional>

class SD;

class PartitionTable {
public:
    PartitionTable(const SD &sd, size_t partitionTableBlock);
};

class Partition {
};

extern std::optional<PartitionTable> partitionTable;
