ARCH=-march=rv32i
ABI=-mabi=ilp32

AM_CCASFLAGS=$(ARCH) $(ABI)
AM_CXXFLAGS=$(ARCH) $(ABI)
AM_CFLAGS=$(ARCH) $(ABI)
AM_CPPFLAGS=-I$(top_srcdir)/include

noinst_PROGRAMS=bl1.elf

REMOVED_SECTIONS=
TOOLCHAIN_PATH=/opt/riscv
TOOLCHAIN_LIB_PATH=$(TOOLCHAIN_PATH)/lib/gcc/$(HOST_TRIPLET)/14.2.0

COMMON=$(top_srcdir)/common

%.coe: %.raw
	sed -e '$$s:,:;:' "$<" > "$@".tmp
	mv "$@".tmp "$@"

%.mif: %.bin
	hexdump -v -e '1/4 "%08x" "\n"' "$<" | $(srcdir)/makemif > "$@".tmp
	mv "$@".tmp "$@"

%.raw: %.bin
	echo -e 'memory_initialization_radix = 16;\nmemory_initialization_vector =' > "$@".tmp
	hexdump -v -e '1/4 "  %08x" ",\n"' "$<" >> "$@".tmp
	mv "$@".tmp "$@"

bl1.mem: bl1.bin
	hexdump -v -e '4/4 "%08x" "\n"' "$<" | sed -e 's:^\(........\)\(........\)\(........\)\(........\)$$:\4\3\2\1: ; s: :0:g' > "$@".tmp
	mv "$@".tmp "$@"

bl1.bin: bl1.elf
	$(HOST_TRIPLET)-objcopy -O binary "$<" "$@" $(foreach rem,$(REMOVED_SECTIONS), --remove-section="$(rem)")

bl1_elf_SOURCES=bl1_main.cpp uart.cpp $(COMMON)/format.cpp ddr.cpp $(COMMON)/gpio.cpp irq.cpp $(COMMON)/reg.cpp $(COMMON)/spi.cpp \
                $(COMMON)/spi_flash.cpp elf_reader.cpp memtest.cpp start.s
EXTRA_bl1_elf_DEPENDENCIES=$(srcdir)/bl1.ld
bl1_elf_LDFLAGS=-T $(srcdir)/bl1.ld --orphan-handling=error
bl1_elf_LDADD=$(TOOLCHAIN_LIB_PATH)/libgcc.a $(TOOLCHAIN_PATH)/$(HOST_TRIPLET)/lib/libc.a

bl1.elf$(EXEEXT): $(bl1_elf_OBJECTS) $(EXTRA_bl1_elf_DEPENDENCIES)
	$(HOST_TRIPLET)-ld $(LDFLAGS) $(AM_LDFLAGS) $(bl1_elf_LDFLAGS) -melf32lriscv $(bl1_elf_OBJECTS) -o "$@" $(bl1_elf_LDADD)

clean-local:
	$(RM) *.mem *.coe *.bin *.raw *.mif
