# What's all this?

This project is the base project from which all CompuSAR computers derive. It's a SystemVerilog implementation of a RiscV CPU for the CompuSAR FPGA (a Spartan-7 board from QMTech). This project contains only the "overhead" part: the 32 bit parts that are meant to communicate with the hardware. The payload parts, the 8-bit computers implemented, are in separate repositories forked from this one.

## How to checkout and build
Follow the following steps to build the project:

### Prerequisits
* If you want to change the software running you'll need the `riscv32-unknown-elf` toolchain. The makefiles search for it in the path, but there is a script called `setpath` in the root of the project that adds `/opt/riscv/bin` to the search path.

### Checking out
* Run `git clone https://github.com/CompuSAR/control_cpu.git`
* Run `git submodule update --init --recursive` to get all dependent projects.

### Modifying the software
* In the root of the project, run `make`. This will generate both the bootloader image (at `CompuSar.srcs/saros/boot_loader_state.mem`) and an MCS file for the actual OS (at `CompuSar.gen/saros/saros.mcs`).
  * The bootloader image needs to be up to date before synthesizing the design, as it gets baked into the bit file.
  * The OS image can be flashed to the FPGA's configuration flash independently from the FPGA configuration.
* Source files for the bootloader are under `CompuSar.srcs/saros/bl1`
* Source files for the OS are under `CompuSar.srcs/saros/saros`

### Building the FPGA image
* Open the project from the `CompuSar.xpr` file in the root of the source tree.
  * The project references a file called `top.dcp` under the "Utility sources" section. This is a generated file that is not checked into the source control. To build the project for the first time you'll need to delete the file from the project. Once deleted it will get recreated the first time you build. Vivado manages this file automatically, and there is nothing you'll need to do.
* You can either generate an MCS and flash it to the board or use the hardware manager to load the bit file directly.
  * This only covers the hardware and bootloader.
* Notice that Vivado doesn't track the bootloader for changes. If you rebuild only the bootloader, you'll need to manually resynthesize the whole project for it to update.
  * Directly updating the COE file from the makefile did not work for me. Suggestions welcome.

## License
All of my code in this repository is licensed under the GPL-3. 3rd party code is licensed under the license of the corresponding project.
