SUBDIRS=kernel .

AM_CCASFLAGS=$(ARCH) $(ABI)
AM_CXXFLAGS=$(ARCH) $(ABI)
AM_CFLAGS=$(ARCH) $(ABI)
AM_CPPFLAGS=-I$(top_srcdir)/include -DSAROS

REMOVED_SECTIONS=
TOOLCHAIN_PATH=/opt/riscv
TOOLCHAIN_LIB_PATH=$(TOOLCHAIN_PATH)/lib/gcc/$(HOST_TRIPLET)/14.2.0

commondir=$(top_srcdir)/common

ARCH=-march=rv32i
ABI=-mabi=ilp32

noinst_PROGRAMS=saros.elf

saros_elf_SOURCES=main.cpp uart.cpp saros.cpp $(commondir)/format.cpp irq.cpp $(commondir)/reg.cpp $(commondir)/gpio.cpp \
                  start.s ../abort.cpp display.cpp crt.cpp \
                  apple2.cpp apple2_display.cpp roms/Apple2_Plus_rom.s roms/charset_us_bin.s
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

$(srcdir)/roms/%.rom:
	wget 'https://github.com/AppleWin/AppleWin/raw/refs/heads/master/resource/$*.rom' -O '$@'.tmp
	mv '$@.tmp' '$@'
.PRECIOUS: $(srcdir)/roms/%.rom

roms/%_rom.s: $(srcdir)/roms/%.rom $(srcdir)/roms/assemblify
	mkdir -p roms
	$(srcdir)/roms/assemblify --section '.apple2_rom' '$<' '$@'

roms/%_bin.s: $(srcdir)/roms/%.bin $(srcdir)/roms/assemblify
	mkdir -p roms
	$(srcdir)/roms/assemblify --section '.charset' '$<' '$@'
