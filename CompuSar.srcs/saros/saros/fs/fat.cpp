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
    char        bs_filSysType[8];
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
    uint8_t     bs_bootSig;
    uint32_t    bs_volId;
    char        bs_volLab[11];
    char        bs_filSysType[8];
#endif
};

#ifndef FAT32
static_assert( sizeof(BPB)==55, "BPB is the wrong size" );
#else
static_assert( sizeof(BPB)==90, "BPB is the wrong size" );
#endif

FAT::FAT(const Partition &partition) :
    partition_(partition)
{
    auto block = partition.readBlock(0);
    // dump_memory(block->data);

    auto bpb = reinterpret_cast<const BPB *>(block->data.data());
    uart_send("  OEM name: ");
    for( unsigned i=0; i<8; ++i )
        uart_send(bpb->bs_oemName[i]);
    uart_send("\n  Bytes per sector: ");
    print_dec(bpb->bpb_bytesPerSec);
    uart_send("\n  Sectors per cluster: ");
    print_dec(bpb->bpb_secPerClus);
    uart_send("\n  Reserved sectors: ");
    print_dec(bpb->bpb_rsvdSecCnt);
    uart_send("\n  Num FATs: ");
    print_dec(bpb->bpb_numFATs);
    uart_send("\n  Root entry count: ");
    print_dec(bpb->bpb_rootEndCnt);
    uart_send("\n  Total sectors 16: ");
    print_dec(bpb->bpb_totSec16);
    uart_send(" 32: ");
    print_dec(bpb->bpb_totSec32);
    uart_send("\n  FAT size 16: ");
    print_dec(bpb->bpb_fatSz16);
    uart_send(" 32: ");
    print_dec(bpb->bpb_fatSz32);
    uart_send("\n  flags: ");
    print_hex(bpb->bpb_extFlags);
    uart_send("\n  FS version: ");
    print_hex(bpb->bpb_fsVer);
    uart_send("\n  Root cluster no: ");
    print_dec(bpb->bpb_rootClus);
    uart_send("\n  FS info cluster no: ");
    print_dec(bpb->bpb_fsInfo);
    uart_send("\n  Backup boot sec: ");
    print_dec(bpb->bpb_bkBootSec);
    uart_send("\n  Boot signature: ");
    print_hex(bpb->bs_bootSig);
    uart_send("\n  Volume ID: ");
    print_hex(bpb->bs_volId);
    uart_send("\n  Volume label: ");
    for(unsigned i=0; i<11; ++i) {
        uart_send(bpb->bs_volLab[i]);
    }
    uart_send("\n  FS type: ");
    for(unsigned i=0; i<8; ++i) {
        uart_send(bpb->bs_filSysType[i]);
    }
    uart_send("\n");

    // Sanity check the BPB
    if( block->data[0x1fe]!=0x55 || block->data[0x1ff]!=0xaa ) {
        uart_send("E: Boot block magic signature not found\n");
        return;
    }
    if( bpb->bpb_secPerClus!=SECT_PER_CLUSTER ) {
        uart_send("E: Only 1 sector per cluster is supported\n");
        return;
    }
    if( bpb->bpb_rootClus!=RootDirCluster.num ) {
        uart_send("E: Root dir cluster isn't 2\n");
        return;
    }
    if( bpb->bpb_fatSz16!=0 ) {
        uart_send("E: 16 bit FAT size must be 0\n");
        return;
    }
    if( bpb->bpb_rootEndCnt!=0 ) {
        uart_send("E: Root dir entries must be 0 for FAT32 filesystems\n");
        return;
    }
    if( bpb->bpb_totSec16!=0 ) {
        uart_send("E: 16 bit total sectors must be 0 for FAT32 filesystem\n");
        return;
    }
    uint32_t totalSectors = bpb->bpb_totSec32;
    if( totalSectors>partition_.size() ) {
        uart_send("E: Corrupt: FS size is bigger than the partition size\n");
        return;
    }
    uint32_t firstFatSector = bpb->bpb_rsvdSecCnt;
    uint32_t firstDataSector = firstFatSector + bpb->bpb_numFATs * bpb->bpb_fatSz32; // + root dir sectors that is 0 for FAT32
    if( firstDataSector>partition_.size() ) {
        uart_send("E: Invalid data sectors start\n");
        return;
    }

    uint32_t numClusters = (totalSectors - firstDataSector) * SECT_PER_CLUSTER;

    // Microsoft's totally strange way of determining FS type
    if( numClusters<65525 ) {
        uart_send("D: num clusters ");
        print_dec(numClusters);
        uart_send("\n");

        uart_send("E: FS is not FAT32 by size\n");
        return;
    }

    uint32_t numFatSectors = (numClusters + CLUSTERS_PER_FAT_SECTOR - 1)/CLUSTERS_PER_FAT_SECTOR;
    if( bpb->bpb_fatSz32 < numFatSectors ) {
        uart_send("E: FAT area isn't big enough for the required FAT entries\n");
        return;
    }

    auto fat = partition_.readBlock(firstFatSector);

    uint32_t mediaState = reinterpret_cast<const uint32_t *>(fat->data.data())[1];
    if( (mediaState & 0x08000000)==0 ) {
        uart_send("E: FAT partition is not clean\n");
        return;
    }
    if( (mediaState & 0x04000000)==0 ) {
        uart_send("E: Bad sectors reported on volume\n");
        return;
    }

    firstDataSector_ = firstDataSector;
    firstFatSector_ = firstFatSector;
    totalSectors_ = totalSectors;
}

SD::BlockPtr FAT::readCluster(ClusterNum clusterNum) const {
    uint32_t sectorNum = ((clusterNum.num - FIRST_USABLE_CLUSTER) * SECT_PER_CLUSTER) + firstDataSector_;

    return partition_.readBlock(sectorNum);
}

FAT::ClusterNum FAT::nextCluster(ClusterNum cluster) const {
    assertWithMessage(cluster.num < totalSectors_, "Asked for next cluster of cluster that is out of range");

    uint32_t fatSectorNum = cluster.num / CLUSTERS_PER_FAT_SECTOR;
    auto fatSector = partition_.readBlock(firstFatSector_ + fatSectorNum);

    uint32_t clusterInFat = cluster.num % fatSectorNum;
    uint32_t nextCluster = reinterpret_cast<const uint32_t *>(fatSector->data.data())[clusterInFat];

    return ClusterNum(nextCluster);
}

void FAT::Directory::dir() const {
    bool done = false;

    ClusterNum dirCluster = dirStart_;
    while( !done && dirCluster.isValid() ) {
        auto dirBuffer = fs_.readCluster(dirCluster);
        auto dirEntries = reinterpret_cast<const DirEntry *>(dirBuffer->data.data());

        for( unsigned i=0; i<DirEntriesPerSector; ++i ) {
            const DirEntry &entry = dirEntries[i%DirEntriesPerSector];
            if( entry.dirName[0]==DirEntry::EndMarker ) {
                done = true;
                break;
            }
            if( entry.dirName[0]==DirEntry::FreeMarker )
                continue;
            if( (entry.dirAttr & DirEntry::AttributeLongName) == DirEntry::AttributeLongName )
                continue;

            for(unsigned j=0; j<8; ++j) {
                uart_send(entry.dirName[j]);
            }
            uart_send("     ");
            for(unsigned j=8; j<11; ++j) {
                uart_send(entry.dirName[j]);
            }
            uart_send("  ");

            if( entry.dirAttr & DirEntry::AttrArchive ) {
                uart_send('A');
            } else {
                uart_send('-');
            }

            if( entry.dirAttr & DirEntry::AttrDirectory ) {
                uart_send('D');
            } else {
                uart_send('-');
            }

            if( entry.dirAttr & DirEntry::AttrVolumeId ) {
                uart_send('V');
            } else {
                uart_send('-');
            }

            if( entry.dirAttr & DirEntry::AttrSystem ) {
                uart_send('S');
            } else {
                uart_send('-');
            }

            if( entry.dirAttr & DirEntry::AttrHidden ) {
                uart_send('H');
            } else {
                uart_send('-');
            }

            if( entry.dirAttr & DirEntry::AttrReadOnly ) {
                uart_send('R');
            } else {
                uart_send('-');
            }

            uart_send("   ");
            print_dec(dirEntries[i].dirFileSize);

            uart_send("\n");
        }

        if( !done ) {
            dirCluster = fs_.nextCluster(dirCluster);
        }
    }
}
