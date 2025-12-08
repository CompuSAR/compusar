#include "elf_reader.h"

#include "format.h"
#include "irq.h"
#include "spi_flash.h"
#include "uart.h"

#include <elf.h>

#include <stddef.h>

extern uint8_t OS_LOAD_BUFFER[], OS_LOAD_BUFFER_END[];

namespace ElfReader {

static constexpr uint32_t OS_FLASH_ADDRESS = 0x400000;  // 4MB into the flash

template<typename T>
static void check_value(T value, T desired) {
    if( value!=desired ) {
        uart_send("Expected to get ");
        print_hex(desired);
        uart_send(". Instead got ");
        print_hex(value);
        uart_send(".\n");

        SPI_FLASH::deinit();
        halt();
    }
}

template<typename T>
static const T *by_offset(const uint8_t *base, size_t offset) {
    return reinterpret_cast<const T*>(base + offset);
}

// Return the entry point, or null if there was a problem
EntryPoint load_os() {
    const size_t BufferSize = &OS_LOAD_BUFFER_END[0] - &OS_LOAD_BUFFER[0];

    struct HeaderBuffer {
        Elf32_Ehdr header;
        char padding[ 16 - (sizeof(Elf32_Ehdr) % 16) ];
    } __attribute__(( aligned(16) ));

    HeaderBuffer headerBuffer;

    SPI_FLASH::initiate_read(OS_FLASH_ADDRESS, sizeof(Elf32_Ehdr), &headerBuffer);
    SPI_FLASH::wait_done();

    const Elf32_Ehdr &header = headerBuffer.header;

    check_value<unsigned char>(header.e_ident[EI_MAG0], 0x7f);
    check_value<unsigned char>(header.e_ident[EI_MAG1], 'E');
    check_value<unsigned char>(header.e_ident[EI_MAG2], 'L');
    check_value<unsigned char>(header.e_ident[EI_MAG3], 'F');
    check_value<unsigned char>(header.e_ident[EI_CLASS], ELFCLASS32 );
    check_value<Elf32_Half>(header.e_ehsize, sizeof(Elf32_Ehdr));
    check_value<unsigned char>(header.e_ident[EI_DATA], ELFDATA2LSB );
    check_value<unsigned char>(header.e_ident[EI_VERSION], EV_CURRENT );
    check_value<unsigned char>(header.e_ident[EI_OSABI], ELFOSABI_NONE );
    check_value<unsigned char>(header.e_ident[EI_ABIVERSION], 0 );
    check_value<Elf32_Half>(header.e_type, ET_EXEC);
    check_value<Elf32_Half>(header.e_machine, EM_RISCV);
    check_value<Elf32_Word>(header.e_version, EV_CURRENT);

    auto entry_point = reinterpret_cast<EntryPoint>(header.e_entry);

    check_value<Elf32_Half>(header.e_phentsize, sizeof(Elf32_Phdr));
    if( header.e_phnum * sizeof(Elf32_Phdr) > BufferSize ) {
        uart_send("ERROR: ELF program section descriptors need ");
        print_hex(header.e_phnum * sizeof(Elf32_Phdr));
        uart_send(" bytes. Num sections ");
        print_hex(header.e_phnum);
        uart_send(".\n");

        SPI_FLASH::deinit();
        halt();
        return nullptr;
    }

    SPI_FLASH::initiate_read(OS_FLASH_ADDRESS + header.e_phoff, sizeof(Elf32_Ehdr)*header.e_phnum, &OS_LOAD_BUFFER[0]);
    SPI_FLASH::wait_done();

    auto program_headers = by_offset<Elf32_Phdr>(OS_LOAD_BUFFER, 0);
    for( unsigned int i=0; i<header.e_phnum; ++i ) {
        uart_send("Program header: type ");
        print_hex(program_headers[i].p_type);
        uart_send(" vaddr ");
        print_hex(program_headers[i].p_vaddr);

        if( program_headers[i].p_type != PT_LOAD ) {
            uart_send(" skipped: not PT_LOAD\n");
            continue;
        }

        if( program_headers[i].p_filesz==0 ) {
            uart_send(" skipped: size 0\n");
            continue;
        }

        SPI_FLASH::wait_done();
        SPI_FLASH::initiate_read(
                program_headers[i].p_offset + OS_FLASH_ADDRESS,
                program_headers[i].p_filesz,
                reinterpret_cast<void *>(program_headers[i].p_vaddr) );

        uart_send(" loaded\n");
    }

    SPI_FLASH::wait_done();
    SPI_FLASH::initiate_read(OS_FLASH_ADDRESS + header.e_shoff, sizeof(Elf32_Shdr)*header.e_shnum, OS_LOAD_BUFFER);
    SPI_FLASH::wait_done();

    auto section_headers = by_offset<Elf32_Shdr>(OS_LOAD_BUFFER, 0);
    for( unsigned int i=0; i<header.e_shnum; ++i ) {
        if( section_headers[i].sh_type != SHT_NOBITS )
            continue;

        uart_send("Clearing BSS section at ");
        print_hex(section_headers[i].sh_addr);
        uart_send(" size ");
        print_hex(section_headers[i].sh_size);
        uart_send("\n");

        unsigned char *section = reinterpret_cast<unsigned char *>( section_headers[i].sh_addr );
        for( unsigned int j=0; j<section_headers[i].sh_size; ++j ) {
            section[j] = 0;
        }
    }

    SPI_FLASH::wait_done();

    return entry_point;
}

} // namespace ElfReader
