#include "elf.h"

#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <iostream>

template<typename T>
bool check_value(T value, T desired) {
    if( value!=desired ) {
        std::cerr<<"Expected to get "<<(uint64_t)desired<<", got "<<(uint64_t)value<<"\n";

        exit(2);
    }

    return true;
}

template<typename T>
const T *by_offset(const void *base, size_t offset) {
    intptr_t base_i = reinterpret_cast<intptr_t>(base);
    return reinterpret_cast<const T*>(base_i + offset);
}

int main(int argc, char *argv[]) {
    int fd = open(argv[1], O_RDONLY);
    if( fd==-1 ) {
        perror("Failed to open file");
        return 1;
    }

    struct stat s;
    if( fstat(fd, &s)==-1 ) {
        perror("Failed to stat");
        return 1;
    }

    const void *map = mmap(nullptr, s.st_size, PROT_READ, MAP_SHARED|MAP_FILE, fd, 0);
    if( map==MAP_FAILED ) {
        perror("Map failed");
        return 1;
    }

    auto header = reinterpret_cast<const Elf32_Ehdr *>(map);
    check_value<unsigned char>(header->e_ident[EI_MAG0], 0x7f);
    check_value<unsigned char>(header->e_ident[EI_MAG1], 'E');
    check_value<unsigned char>(header->e_ident[EI_MAG2], 'L');
    check_value<unsigned char>(header->e_ident[EI_MAG3], 'F');
    check_value<unsigned char>(header->e_ident[EI_CLASS], ELFCLASS32 );
    check_value<unsigned char>(header->e_ident[EI_DATA], ELFDATA2LSB );
    check_value<unsigned char>(header->e_ident[EI_VERSION], EV_CURRENT );
    check_value<unsigned char>(header->e_ident[EI_OSABI], ELFOSABI_NONE );
    check_value<unsigned char>(header->e_ident[EI_ABIVERSION], 0 );
    check_value<Elf32_Half>(header->e_type, ET_EXEC);
    check_value<Elf32_Half>(header->e_machine, EM_RISCV);
    check_value<Elf32_Word>(header->e_version, EV_CURRENT);
    check_value<Elf32_Half>(header->e_ehsize, sizeof(Elf32_Ehdr));

    std::cout<<std::hex<<"Entry point: 0x"<<header->e_entry<<std::dec<<"\n";
    std::cout<<"Section header offset: "<<header->e_shoff<<"\n";

    check_value<Elf32_Half>(header->e_phentsize, sizeof(Elf32_Phdr));
    auto program_headers = by_offset<Elf32_Phdr>(map, header->e_phoff);

    for( unsigned int i=0; i<header->e_phnum; ++i ) {
        std::cerr<<std::dec<<"Segment "<<i<<" type "<<std::hex<<program_headers[i].p_type<<" flags "<<program_headers[i].p_flags
                <<" file offset "<<program_headers[i].p_offset<<" vaddr "<<program_headers[i].p_vaddr
                <<std::dec<<" file size "<<program_headers[i].p_filesz
                <<" mem size "<<program_headers[i].p_memsz<<"\n";
    }

    check_value<Elf32_Half>(header->e_shentsize, sizeof(Elf32_Shdr));
    auto section_headers = by_offset<Elf32_Shdr>(map, header->e_shoff);

    for( unsigned int i=0; i<header->e_shnum; ++i ) {
        std::cerr<<std::dec<<"Section "<<i<<" type "<<std::hex<<section_headers[i].sh_type
                <<" flags "<<section_headers[i].sh_flags<<" addr "<<section_headers[i].sh_addr
                <<" size "<<section_headers[i].sh_size<<"\n";
    }

    //std::cout<<sizeof(ELF::Ident)<<"\n";
}
