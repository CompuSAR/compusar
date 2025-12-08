CROSS=riscv32-unknown-elf-

AS=$(CROSS)as
ASFLAGS=

testprog.mem: testprog.bin
	hexdump -v -e '1/4 "%08x" "\n"' $< > $@.tmp
	mv $@.tmp $@

testprog.bin: testprog.elf
	$(CROSS)objcopy -O binary $< $@

testprog.elf: testprog.o
	$(CROSS)ld -T testprog.ld $< -o $@

clean:
	$(RM) *.o *.elf *.bin *.mem
.PHONY: clean
