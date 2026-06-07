#include <saros/fs/partition.h>

#include "format.h"
#include "dbglogger.hh"
#include "format.h"
#include "sd.h"
#include "uart.h"
#include "saros/saros.h"

#include <string.h>

std::optional<PartitionTable> partitionTable;

PartitionTable::PartitionTable(const SD &sd, size_t partitionTableBlock) : sd_{sd} {
    SD::BlockPtr mbr = sd.readBlock(partitionTableBlock);
    if( !mbr ) {
        uart_send("E: Failed to read MBR\n");

        return;
    }

    if( mbr->data[0x1fe]!=0x55 || mbr->data[0x1ff]!=0xaa ) {
        uart_send("Invalid MBR signature\n");

        return;
    }

    uart_send("Partition table:\n");
    //dump_memory(mbr->data);

    static constexpr size_t FirstPartitionMbrOffset = 0x1be;
    size_t offset = FirstPartitionMbrOffset;
    for( int i=0; i<4; ++i ) {
        PartitionLine part;

        static_assert(std::is_trivially_copyable_v<PartitionLine>, "Can't memcpy PartitionLine");
        static_assert(std::is_standard_layout_v<PartitionLine>, "PartitionLine isn't stabely defined");
        memcpy(&part, &mbr->data.at(offset), sizeof(part));
        offset += sizeof(part);

        uart_send("  ");
        print_dec(i);
        uart_send(": Boot: ");
        print_hex(part.boot);
        uart_send(" Start: H:");
        print_hex(part.start.getHead());
        uart_send(" C:");
        print_hex(part.start.getCyl());
        uart_send(" S:");
        print_hex(part.start.getSect());

        uart_send(" End: H:");
        print_hex(part.end.getHead());
        uart_send(" C:");
        print_hex(part.end.getCyl());
        uart_send(" S:");
        print_hex(part.end.getSect());

        uart_send(" FS:");
        print_hex(static_cast<uint64_t>(part.fsType));

        uart_send(" Start: ");
        print_hex(part.offset);
        uart_send(" Size: ");
        print_hex(part.size);
        uart_send("\n");

        if( part.fsType!=FsType::Unused ) {
            // Sanity checks
            if( part.offset>=sd.getNumBlocks() ) {
dumpdbglogger();
halt();

                uart_send("E: LBA offset points past the end of the device\n");
                part.fsType = FsType::Unused;
            }

            if( part.offset==0 ) {
                uart_send("E: LBA offset is zero\n");
                part.fsType = FsType::Unused;
            }

            if( part.size==0 ) {
                uart_send("E: LBA size is zero\n");
                part.fsType = FsType::Unused;
            }

            if( part.offset + part.size >= sd.getNumBlocks() ) {
                uart_send("E: Partition end past the end of the device\n");
                part.fsType = FsType::Unused;
            }
        }

        if( part.fsType!=FsType::Unused ) {
            partitions_[i] = part;
            maxPartition_ = i+1;
        }
    }
    // TODO if there are extended partitions, we should scan them as well.
}

const PartitionTable::PartitionLine &PartitionTable::at(size_t index) const {
    assertWithMessage( index<maxPartition_, "F: Partition table index out of range" );

    return partitions_[index];
}

Partition::Partition(const SD &sd, size_t offset, size_t size) : sd_{sd}, offset_{offset}, size_{size}
{
    assertWithMessage( offset<sd.getNumBlocks(), "Partition initialized with bad offset argument" );
    assertWithMessage( (offset+size) < sd.getNumBlocks(), "Partition initialized with bad size" );
}

SD::BlockPtr Partition::readBlock(size_t blockNum) const {
    assertWithMessage( blockNum<size_, "Partition readBlock out of range" );

    return sd_.readBlock( blockNum + offset_ );
}
