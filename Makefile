PROJNAME=CompuSar
BUILDDIR=$(PROJNAME).gen/saros
SRCDIR=$(PROJNAME).srcs/saros
all: $(SRCDIR)/boot_loader_state.mem $(BUILDDIR)/saros.mcs $(BUILDDIR)/saros.mem

$(BUILDDIR)/Makefile:
	echo building
	mkdir -p $(BUILDDIR)
	cmake -B $(BUILDDIR) -S $(SRCDIR)

$(BUILDDIR)/saros.mcs $(BUILDDIR)/saros.mem: $(BUILDDIR)/Makefile
	$(MAKE) -C "$(@D)" "saros_images"
.PHONY: $(BUILDDIR)/saros.mcs $(BUILDDIR)/saros.mem

$(BUILDDIR)/bl1.mem: $(BUILDDIR)/Makefile
	$(MAKE) -C "$(@D)" "bl1_images"
.PHONY: $(BUILDDIR)/bl1.mem

$(SRCDIR)/boot_loader.mem: $(BUILDDIR)/bl1.mem
	cp "$<" "$@"

$(SRCDIR)/boot_loader_state.mem: $(SRCDIR)/boot_loader.mem
	#scripts/gen_cache_metadata.py `cat $< | wc -l` 13 0 2048 > $@.tmp	 # 32KB cache
	scripts/gen_cache_metadata.py `cat $< | wc -l` 14 0 1024 > $@.tmp	# 16KB cache
	#scripts/gen_cache_metadata.py `cat $< | wc -l` 15 0 512 > $@.tmp	 # 8KB cache
	mv $@.tmp $@

clean:
	$(RM) -r $(BUILDDIR)

distclean: clean
	$(RM) $(BUILDDIR)/Makefile

.PHONY: clean distclean
