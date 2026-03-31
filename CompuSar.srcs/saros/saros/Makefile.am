SUBDIRS=kernel .

AM_CCASFLAGS=$(ARCH) $(ABI)
AM_CXXFLAGS=$(ARCH) $(ABI)
AM_CFLAGS=$(ARCH) $(ABI)
AM_CPPFLAGS=-I$(top_srcdir)/include -DSAROS

ASSEMBLIFY=$(top_srcdir)/tools/assemblify

REMOVED_SECTIONS=
TOOLCHAIN_PATH=/opt/riscv
TOOLCHAIN_LIB_PATH=$(TOOLCHAIN_PATH)/lib/gcc/$(HOST_TRIPLET)/14.2.0

commondir=$(top_srcdir)/common

ARCH=-march=rv32i
ABI=-mabi=ilp32

noinst_PROGRAMS=saros.elf

saros_elf_SOURCES=main.cpp uart.cpp saros.cpp mutex.cpp $(commondir)/format.cpp irq.cpp $(commondir)/reg.cpp $(commondir)/gpio.cpp \
                  start.s ../abort.cpp display.cpp crt.cpp sd.cpp \
                  assets/logo.cpp
EXTRA_saros_elf_DEPENDENCIES=$(srcdir)/saros.ld kernel/libkernel.a
saros_elf_LDFLAGS=-T $(srcdir)/saros.ld --orphan-handling=error
saros_elf_LDADD=$(TOOLCHAIN_LIB_PATH)/libgcc.a $(TOOLCHAIN_PATH)/$(HOST_TRIPLET)/lib/libc.a kernel/libkernel.a

main.$(OBJEXT): assets/logo.h

saros.elf$(EXEEXT): $(saros_elf_OBJECTS) $(EXTRA_saros_elf_DEPENDENCIES)
	$(HOST_TRIPLET)-ld $(LDFLAGS) $(AM_LDFLAGS) $(saros_elf_LDFLAGS) -melf32lriscv $(saros_elf_OBJECTS) -o "$@" $(saros_elf_LDADD)

saros.bin: saros.elf$(EXEEXT)
	cp $< $@.tmp
	$(HOST_TRIPLET)-strip $@.tmp
	mv $@.tmp $@

kernel/%:
	$(MAKE) -C kernel "$*"

assets/%.cpp assets/%.h: $(srcdir)/assets/%.png $(top_srcdir)/tools/png2source
	mkdir -p assets
	$(top_srcdir)/tools/png2source $< assets/$*.cpp

roms/%_rom.s: $(srcdir)/roms/%.rom $(ASSEMBLIFY)
	mkdir -p roms
	$(ASSEMBLIFY) --section '.apple2_rom' '$<' '$@'

roms/%_bin.s: $(srcdir)/roms/%.bin $(ASSEMBLIFY)
	mkdir -p roms
	$(ASSEMBLIFY) --section .rodata --align 16 --symbol '$*' '$<' '$@'

roms/%_bin.s: $(srcdir)/roms/%_rev7.bin $(ASSEMBLIFY)
	mkdir -p roms
	$(ASSEMBLIFY) --section .rodata --reverse7 --align 16 --symbol '$*' '$<' '$@'
