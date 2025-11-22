PROJNAME=CompuSar
all: $(PROJNAME).srcs/saros/boot_loader_state.mem $(PROJNAME).gen/saros/saros.mcs $(PROJNAME).gen/saros/saros.mem

$(PROJNAME).runs/$(PROJNAME).mcs:

$(PROJNAME).gen/saros/%: $(PROJNAME).gen/saros/config.log
	$(MAKE) -C "$(@D)" "$(@F)"

$(PROJNAME).gen/saros/saros.mcs: $(PROJNAME).gen/saros/config.log
	$(MAKE) -C "$(@D)" "$(@F)"
.PHONY: $(PROJNAME).gen/saros/saros.mcs

$(PROJNAME).gen/saros/saros.mem: $(PROJNAME).gen/saros/config.log
	$(MAKE) -C "$(@D)" "$(@F)"
.PHONY: $(PROJNAME).gen/saros/saros.mem

$(PROJNAME).gen/saros/bl1/bl1.coe: $(PROJNAME).gen/saros/config.log
	$(MAKE) -C "$(@D)" "$(@F)"

.PHONY: $(PROJNAME).gen/saros/bl1/bl1.coe

$(PROJNAME).gen/saros/bl1/bl1.mem: $(PROJNAME).gen/saros/config.log
	$(MAKE) -C "$(@D)" "$(@F)"

.PHONY: $(PROJNAME).gen/saros/bl1/bl1.mem

$(PROJNAME).gen/saros/config.log: $(PROJNAME).srcs/saros/configure
	$(RM) -r $(@D)
	mkdir -p $(@D)
	cd $(@D) && ../../$(PROJNAME).srcs/saros/configure --host=riscv32-unknown-elf

$(PROJNAME).srcs/saros/configure:
	cd $(@D) && autoreconf -i

%/dir.tag:
	mkdir -p "$(@D)"
	@touch "$@"

$(PROJNAME).gen/saros/bl1/mif.tag: $(PROJNAME).gen/saros/bl1/bl1.mif
	find -name blk_mem.mif -print0 | xargs -0 --no-run-if-empty -n1 cp -a $<
	touch $@

$(PROJNAME).gen/saros/bl1/bl1.mif: $(PROJNAME).gen/saros/config.log
	$(MAKE) -C "$(@D)" "$(@F)"
.PHONY: $(PROJNAME).gen/saros/bl1/bl1.mif

$(PROJNAME).srcs/saros/boot_loader.mem: $(PROJNAME).gen/saros/bl1/bl1.mem
	cp "$<" "$@"

$(PROJNAME).srcs/saros/boot_loader_state.mem: $(PROJNAME).srcs/saros/boot_loader.mem
	#scripts/gen_cache_metadata.py `cat $< | wc -l` 13 0 2048 > $@.tmp	 # 32KB cache
	scripts/gen_cache_metadata.py `cat $< | wc -l` 14 0 1024 > $@.tmp	# 16KB cache
	#scripts/gen_cache_metadata.py `cat $< | wc -l` 15 0 512 > $@.tmp	 # 8KB cache
	mv $@.tmp $@

clean:
	$(RM) -r $(PROJNAME).gen/saros

distclean: clean
	$(RM) $(PROJNAME).gen/saros/config.log
	$(RM) $(PROJNAME).srcs/saros/**.in $(PROJNAME).srcs/saros/configure

.PHONY: clean distclean
