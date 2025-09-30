set_property IOSTANDARD LVCMOS33 [get_ports leds*]
set_property IOSTANDARD LVCMOS33 [get_ports switches*]
set_property IOSTANDARD LVCMOS33 [get_ports spi_*]
create_clock -period 20.000 [get_ports board_clock]
set_property PACKAGE_PIN Y18 [get_ports board_clock]
set_property IOSTANDARD LVCMOS33 [get_ports board_clock]

set_property PACKAGE_PIN F20 [get_ports nReset]
set_property IOSTANDARD LVCMOS33 [get_ports nReset]

set_property PACKAGE_PIN F19 [get_ports {leds[0]}]
set_property PACKAGE_PIN E21 [get_ports {leds[1]}]
set_property PACKAGE_PIN D20 [get_ports {leds[2]}]
set_property PACKAGE_PIN C20 [get_ports {leds[3]}]

set_output_delay -clock [get_clocks board_clock] -min -add_delay -2.000 [get_ports {leds[3]}]
set_output_delay -clock [get_clocks board_clock] -max -add_delay 2.000 [get_ports {leds[3]}]

set_property PACKAGE_PIN M13 [get_ports {switches[0]}]
set_property PACKAGE_PIN K14 [get_ports {switches[1]}]
set_property PACKAGE_PIN K13 [get_ports {switches[2]}]
set_property PACKAGE_PIN L13 [get_ports {switches[3]}]

set_property PACKAGE_PIN F16 [get_ports {debug[0]}]
#set_property PACKAGE_PIN L12 [get_ports {debug[1]}]
set_property PACKAGE_PIN F18 [get_ports {debug[1]}]
set_property PACKAGE_PIN E19 [get_ports {debug[2]}]
set_property PACKAGE_PIN D17 [get_ports {debug[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {debug[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {debug[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {debug[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {debug[0]}]

set_property PACKAGE_PIN G15 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

set_property PACKAGE_PIN G16 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

set_property PACKAGE_PIN T19 [get_ports spi_cs_n]
# set_property PACKAGE_PIN L12 [get_ports spi_clk]
set_property PACKAGE_PIN P22 [get_ports {spi_dq[0]}]
set_property PACKAGE_PIN R22 [get_ports {spi_dq[1]}]
set_property PACKAGE_PIN P21 [get_ports {spi_dq[2]}]
set_property PACKAGE_PIN R21 [get_ports {spi_dq[3]}]

############ Numeric display ############
set_property PACKAGE_PIN H4 [get_ports {numeric_segments_n[0]}]
set_property PACKAGE_PIN K3 [get_ports {numeric_segments_n[1]}]
set_property PACKAGE_PIN K6 [get_ports {numeric_segments_n[2]}]
set_property PACKAGE_PIN G4 [get_ports {numeric_segments_n[3]}]
set_property PACKAGE_PIN H5 [get_ports {numeric_segments_n[4]}]
set_property PACKAGE_PIN J6 [get_ports {numeric_segments_n[5]}]
set_property PACKAGE_PIN M3 [get_ports {numeric_segments_n[6]}]
set_property PACKAGE_PIN J5 [get_ports {numeric_segments_n[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_segments_n[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_segments_n[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_segments_n[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_segments_n[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_segments_n[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_segments_n[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_segments_n[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_segments_n[0]}]

set_property PACKAGE_PIN M2 [get_ports {numeric_enable_n[0]}]
set_property PACKAGE_PIN N4 [get_ports {numeric_enable_n[1]}]
set_property PACKAGE_PIN L5 [get_ports {numeric_enable_n[2]}]
set_property PACKAGE_PIN L4 [get_ports {numeric_enable_n[3]}]
set_property PACKAGE_PIN M16 [get_ports {numeric_enable_n[4]}]
set_property PACKAGE_PIN M17 [get_ports {numeric_enable_n[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_enable_n[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_enable_n[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_enable_n[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_enable_n[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_enable_n[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {numeric_enable_n[0]}]

############## NET - IOSTANDARD ##################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]

#############SPI Configurate Setting##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]


create_clock -period 3.265 -name VIRTUAL_ddr_clock -waveform {0.000 1.633}

set_output_delay -clock [get_clocks board_clock] -max -add_delay -1.500 [get_ports {spi_dq[*]}]
#set_output_delay -clock [get_clocks board_clock] -max -add_delay 1.750 [get_ports {spi_dq[*]}]
set_output_delay -clock [get_clocks board_clock] -min -add_delay 0.000 [get_ports spi_cs_n]
set_output_delay -clock [get_clocks board_clock] -max -add_delay 0.000 [get_ports spi_cs_n]

#set_input_delay -clock [get_clocks board_clock] -min -add_delay 2.300 [get_ports {spi_dq[*]}]
#set_input_delay -clock [get_clocks board_clock] -max -add_delay 8.500 [get_ports {spi_dq[*]}]

