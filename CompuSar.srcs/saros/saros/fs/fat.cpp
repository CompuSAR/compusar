#include <saros/fs/fat.h>

#include "format.h"
#include "uart.h"

#include <cstdint>

#define FAT32 1

// Boot sector and BIOS Parameter Block
struct __attribute__((packed)) BPB {
    uint8_t     bs_jmpBoot[3];
    char        bs_oemName[8];
    uint16_t    bpb_bytesPerSec;
    uint8_t     bpb_secPerClus;
    uint16_t    bpb_rsvdSecCnt;
    uint8_t     bpb_numFATs;
    uint16_t    bpb_rootEndCnt;
    uint16_t    bpb_totSec16;
    uint8_t     bpb_media;
    uint16_t    bpb_fatSz16;
    uint16_t    bpb_secPerTrk;
    uint16_t    bpb_numHeads;
    uint32_t    bpb_hiddSec;
    uint32_t    bpb_totSec32;
#ifndef FAT32
    uint8_t     bs_drvNum;
    uint8_t     bs_reserved1;
    uint8_t     bs_bootSig;
    uint32_t    bs_volId;
    char        bs_volLab[11];
    char        bsFilSysType[8];
#else
    uint32_t    bpb_fatSz32;
    uint16_t    bpb_extFlags;
    uint16_t    bpb_fsVer;
    uint32_t    bpb_rootClus;
    uint16_t    bpb_fsInfo;
    uint16_t    bpb_bkBootSec;
    uint8_t     bpb_reserved[12];
    uint8_t     bs_drvNum;
    uint8_t     bs_reserved1;
#endif
};

#ifndef FAT32
static_assert( sizeof(BPB)==55, "BPB is the wrong size" );
#else
static_assert( sizeof(BPB)==66, "BPB is the wrong size" );
#endif

FAT::FAT(const Partition &partition) :
    _partition(partition)
{
    auto block = partition.readBlock(0);
    dump_memory(block->data);

    auto bpb = reinterpret_cast<const BPB *>(block->data.data());
    uart_send("OEM name: ");
    for( unsigned i=0; i<8; ++i )
        uart_send(bpb->bs_oemName[i]);
    uart_send("\nBytes per secotr: ");
    print_dec(bpb->bpb_bytesPerSec);
    uart_send("\n");
}
