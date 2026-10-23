cmake_minimum_required(VERSION 4.0)

# ---------------------------------------------------------------------------
# Cross-compilation setup (must come before project())
# ---------------------------------------------------------------------------
set(CMAKE_SYSTEM_NAME      Generic)   # bare metal: no OS
set(CMAKE_SYSTEM_PROCESSOR riscv32)

set(TRIPLET riscv32-compusar-elf)
set(CMAKE_C_COMPILER   ${TRIPLET}-gcc)
set(CMAKE_CXX_COMPILER ${TRIPLET}-g++)
set(CMAKE_ASM_COMPILER ${TRIPLET}-gcc)

# Bare-metal link steps can't be trusted during CMake's compiler probe;
# build a static library instead of an executable for the checks.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Never pick up host programs/libraries
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

project(saros LANGUAGES C CXX ASM)

# ---------------------------------------------------------------------------
# Target architecture (adjust to match your core)
# ---------------------------------------------------------------------------
set(SAROS_MARCH "rv32i_zicsr" CACHE STRING "RISC-V -march value")
set(SAROS_MABI  "ilp32"    CACHE STRING "RISC-V -mabi value")

set(ARCH_FLAGS -march=${SAROS_MARCH} -mabi=${SAROS_MABI} -specs=picolibcpp.specs)
add_compile_options(${ARCH_FLAGS})
add_link_options(${ARCH_FLAGS})

# ---------------------------------------------------------------------------
# Language / code-gen options
# ---------------------------------------------------------------------------
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Removed: -ffunction-sections -fdata-sections
add_compile_options(
    -Wall -Wextra -Werror
    -O2
    -g
    -flto
    -fno-use-cxa-atexit
    $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions>
    $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>
)

# ---------------------------------------------------------------------------
# Directories
# ---------------------------------------------------------------------------
set(PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." CACHE PATH "Project root directory")

set(COMMON ${CMAKE_CURRENT_SOURCE_DIR}/common CACHE PATH "Sources shared between boot loader and saros")
set(ASSETS_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/saros/assets CACHE PATH "Non code assets")
set(ASSETS_OUTPUT_DIR ${CMAKE_BINARY_DIR}/saros/assets CACHE PATH "Output dir for processed assets")

file(MAKE_DIRECTORY "${ASSETS_OUTPUT_DIR}")

# ---------------------------------------------------------------------------
# Tools and configuration for image generation
# ---------------------------------------------------------------------------
set(SCRIPTS_PATH "" CACHE PATH "Helper scripts path")
if(NOT SCRIPTS_PATH)
    if(DEFINED ENV{SCRIPTS_PATH})
        set(SCRIPTS_PATH "$ENV{SCRIPTS_PATH}")
    else()
        set(SCRIPTS_PATH "${PROJECT_ROOT}/scripts")
    endif()
endif()

set(TOOLS_PATH "" CACHE PATH "Builder tools path")
if(NOT TOOLS_PATH)
    if(DEFINED ENV{TOOLS_PATH})
        set(TOOLS_PATH "$ENV{TOOLS_PATH}")
    else()
        set(TOOLS_PATH "${CMAKE_CURRENT_SOURCE_DIR}/tools")
    endif()
endif()

find_program(OBJCOPY ${TRIPLET}-objcopy REQUIRED)
find_program(STRIP   ${TRIPLET}-strip   REQUIRED)
find_program(HEXDUMP hexdump REQUIRED)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# Load offsets in flash, hex digits without a 0x prefix.
# Keep these in sync with the origins in the linker scripts.
set(SAROS_FLASH_OFFSET "400000" CACHE STRING "saros offset in flash (hex, no 0x)")
set(BL1_FLASH_OFFSET   "0"      CACHE STRING "bl1 offset in flash (hex, no 0x)")

# Sections stripped from bl1.bin by objcopy (the old Makefile's REMOVED_SECTIONS).
# Semicolon-separated list, e.g. -DBL1_REMOVED_SECTIONS=".comment;.riscv.attributes"
set(BL1_REMOVED_SECTIONS "" CACHE STRING "Sections removed from bl1.bin")

# ---------------------------------------------------------------------------
# saros_add_png(<name>
#
# reads in <name>.png, and produces <name>.cc and <name>.hpp that export the
# image's content to the CPP code.
function(saros_add_png NAME)
    cmake_path(GET NAME STEM BASENAME)

    set(out_cc "${ASSETS_OUTPUT_DIR}/${BASENAME}.cc")
    set(out_hpp "${ASSETS_OUTPUT_DIR}/${BASENAME}.hpp")

    add_custom_command(
        OUTPUT "${out_cc}" "${out_hpp}"
        COMMAND "${TOOLS_PATH}/png2source" "${ASSETS_SRC_DIR}/${NAME}" "${out_cc}"
        DEPENDS "${ASSETS_SRC_DIR}/${NAME}" "${TOOLS_PATH}/png2source"
        COMMENT "Importing ${NAME}"
        VERBATIM
    )
endfunction()

# ---------------------------------------------------------------------------
# saros_add_firmware(<name>
#     LINKER_SCRIPT <file.ld>
#     FLASH_OFFSET  <hex digits, no 0x>
#     SOURCES       <files...>
#     [REMOVED_SECTIONS <names...>]
#     [STRIP_ELF]
#     [MCS])
#
# Builds <name>.elf with LTO and the given linker script, then derives:
#     <name>.bin  (objcopy -O binary by default; with STRIP_ELF it is
#                  instead the ELF itself, stripped, still in ELF format).
#                  REMOVED_SECTIONS adds --remove-section=<name> for each
#                  entry to the objcopy command (not used with STRIP_ELF).
#     <name>.mem  (always)
#     <name>.mcs  (only if MCS is given)
# All images are built as part of "all".
# ---------------------------------------------------------------------------
function(saros_add_firmware NAME)
    cmake_parse_arguments(FW "MCS;STRIP_ELF" "LINKER_SCRIPT;FLASH_OFFSET;SOURCE_DIR" "SOURCES;REMOVED_SECTIONS" ${ARGN})

    set(REL_SOURCE_DIR "${FW_SOURCE_DIR}")

    # Base for relative paths: SOURCE_DIR (itself relative to the current
    # source dir if not absolute), else the current source dir.
    if(NOT FW_SOURCE_DIR)
        set(FW_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    endif()
    cmake_path(ABSOLUTE_PATH FW_SOURCE_DIR
               BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" NORMALIZE)

    set(abs_sources "")
    foreach(src IN LISTS FW_SOURCES)
        cmake_path(ABSOLUTE_PATH src BASE_DIRECTORY "${FW_SOURCE_DIR}" NORMALIZE)
        list(APPEND abs_sources "${src}")
    endforeach()

    cmake_path(ABSOLUTE_PATH FW_LINKER_SCRIPT
               BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" NORMALIZE
               OUTPUT_VARIABLE ld)

    add_executable(${NAME} ${abs_sources})
    set_target_properties(${NAME} PROPERTIES
        OUTPUT_NAME                  ${NAME}
        SUFFIX                       ".elf"
        INTERPROCEDURAL_OPTIMIZATION ON
        LINK_DEPENDS                 ${ld}        # relink if the script changes
    )
    target_include_directories(${NAME}
        AFTER PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/include/stdc++"
        "${CMAKE_CURRENT_BINARY_DIR}/${REL_SOURCE_DIR}")
    target_compile_definitions(${NAME} PRIVATE _GLIBCXX_NO_ASSERTIONS)

    target_link_options(${NAME} PRIVATE
        -T${ld}
        -Wl,--orphan-handling=error
        -Wl,-Map=$<TARGET_FILE_DIR:${NAME}>/${NAME}.map
        -nostdlib
    )
    target_link_libraries(${NAME} PRIVATE gcc)

    set(bin ${CMAKE_CURRENT_BINARY_DIR}/${NAME}.bin)
    set(mem ${CMAKE_CURRENT_BINARY_DIR}/${NAME}.mem)
    set(mcs ${CMAKE_CURRENT_BINARY_DIR}/${NAME}.mcs)

    # <name>.bin (rebuilt whenever the ELF is relinked)
    if(FW_STRIP_ELF)
        # Stripped ELF: the file stays an ELF, just without symbols/debug info
        add_custom_command(
            OUTPUT  ${bin}
            COMMAND ${STRIP} -o ${bin} $<TARGET_FILE:${NAME}>
            DEPENDS ${NAME}
            COMMENT "Creating ${NAME}.bin (stripped ELF)"
            VERBATIM
        )
    else()
        # Flat raw binary, optionally with some sections removed
        set(remove_args "")
        foreach(sec IN LISTS FW_REMOVED_SECTIONS)
            list(APPEND remove_args "--remove-section=${sec}")
        endforeach()

        add_custom_command(
            OUTPUT  ${bin}
            COMMAND ${OBJCOPY} -O binary $<TARGET_FILE:${NAME}> ${bin} ${remove_args}
            DEPENDS ${NAME}
            COMMENT "Creating ${NAME}.bin (objcopy)"
            VERBATIM
        )
    endif()

    # Verilog-style .mem: "@offset" line followed by 16 hex bytes per line.
    # tmp + mv so a failed run never leaves a truncated output file.
    add_custom_command(
        OUTPUT  ${mem}
        COMMAND sh -c "echo @${FW_FLASH_OFFSET} > \"${mem}.tmp\" && \"${HEXDUMP}\" -ve '16/1 \"%02X \" \"\\n\"' \"${bin}\" >> \"${mem}.tmp\" && mv \"${mem}.tmp\" \"${mem}\""
        DEPENDS ${bin}
        COMMENT "Creating ${NAME}.mem"
        VERBATIM
    )
    set(outputs ${mem})

    if(FW_MCS)
        add_custom_command(
            OUTPUT  ${mcs}
            COMMAND sh -c "\"${Python3_EXECUTABLE}\" \"${SCRIPTS_PATH}/make_hex.py\" --offset 0x${FW_FLASH_OFFSET} \"\" \"${bin}\" > \"${mcs}.tmp\" && mv \"${mcs}.tmp\" \"${mcs}\""
            DEPENDS ${bin} ${SCRIPTS_PATH}/make_hex.py
            COMMENT "Creating ${NAME}.mcs"
            VERBATIM
        )
        list(APPEND outputs ${mcs})
    endif()

    add_custom_target(${NAME}_images ALL DEPENDS ${outputs})
endfunction()

saros_add_png(logo.png)

# ---------------------------------------------------------------------------
# Firmware images
# ---------------------------------------------------------------------------
# Main image: saros.mcs + saros.mem
saros_add_firmware(saros
    SOURCE_DIR    saros
    LINKER_SCRIPT saros/saros.ld
    FLASH_OFFSET  ${SAROS_FLASH_OFFSET}
    SOURCES       start.s main.cpp uart.cpp saros.cpp mutex.cpp
                  ../abort.cpp display.cpp crt.cpp sd.cpp irq.cpp
                  ${COMMON}/format.cpp ${COMMON}/reg.cpp ${COMMON}/gpio.cpp ${COMMON}/string.cpp ${COMMON}/dbglogger.cc
                  ${ASSETS_OUTPUT_DIR}/logo.cc
                  # Saros files
                  kernel/thread.cpp kernel/scheduler.cpp kernel/context.s kernel/thread_queue.cpp kernel/timer.cpp
                  fs/partition.cpp fs/fat.cpp fs/filesystem.cpp
    STRIP_ELF
    MCS
)
target_compile_definitions(saros PRIVATE SAROS=1)

# First-stage bootloader: bl1.mem only
saros_add_firmware(bl1
    SOURCE_DIR    bl1
    LINKER_SCRIPT bl1/bl1.ld
    FLASH_OFFSET  ${BL1_FLASH_OFFSET}
    SOURCES       start.s bl1_main.cpp uart.cpp ${COMMON}/string.cpp
                  ${COMMON}/format.cpp ddr.cpp ${COMMON}/gpio.cpp irq.cpp ${COMMON}/reg.cpp ${COMMON}/spi.cpp
                  ${COMMON}/spi_flash.cpp elf_reader.cpp
    REMOVED_SECTIONS ${BL1_REMOVED_SECTIONS}
)
