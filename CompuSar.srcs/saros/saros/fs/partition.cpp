#include <saros/fs/partition.h>

#include "format.h"
#include "sd.h"
#include "uart.h"

#include <string.h>

std::optional<PartitionTable> partitionTable;

PartitionTable::PartitionTable(const SD &sd, size_t partitionTableBlock) {
    struct PartitionLine {
        enum class FsType : uint8_t {
            Unused = 0x00,
            Extended = 0x05,

            Fat12 = 0x01,
            Fat16 = 0x04,
            Fat32 = 0x06,
            Fat32Lba = 0x0b,
        };
        struct CHS {
            uint8_t data[3];

            uint8_t getHead() const { return data[0]; }
            uint8_t getSect() const { return data[1] & ((1<<6) - 1); }
            uint16_t getCyl() const { return (data[2]<<2) | (data[3]>>6); }
        };

        uint8_t boot;
        CHS start;
        FsType fsType;
        CHS end;

        uint32_t offset;
        uint32_t size;
    };
    static_assert(sizeof(PartitionLine)==16);

    uart_send("Reading in partition table\n");
    SD::BlockPtr mbr = sd.readBlock(0);
    if( !mbr ) {
        uart_send("E: Failed to read MBR\n");

        return;
    }
    dump_memory(mbr->data);

    if( mbr->data[0x1fe]!=0x55 || mbr->data[0x1ff]!=0xaa ) {
        uart_send("Invalid MBR signature\n");

        return;
    }

    uart_send("\nPartition table:\n");

    static constexpr size_t FirstPartitionMbrOffset = 0x1be;
    size_t offset = FirstPartitionMbrOffset;
    for( int i=0; i<4; ++i ) {
        PartitionLine part;

        memcpy(&part, &mbr->data.at(offset), sizeof(part));
        offset += sizeof(part);

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
        print_hex(part.fsType);

        uart_send(" Start: ");
        print_hex(part.offset);
        uart_send(" Size: ");
        print_hex(part.size);
        uart_send("\n");
    }
}
