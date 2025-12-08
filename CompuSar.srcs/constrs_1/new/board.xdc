create_clock -period 20.000 [get_ports board_clock]
set_property PACKAGE_PIN Y18 [get_ports board_clock]

set_property IOSTANDARD LVCMOS33 [get_ports board_clock]

set_property PACKAGE_PIN F20 [get_ports nReset]
set_property IOSTANDARD LVCMOS33 [get_ports nReset]

set_property IOSTANDARD LVCMOS33 [get_ports {leds*}]
set_property PACKAGE_PIN F19 [get_ports {leds[0]}]
set_property PACKAGE_PIN E21 [get_ports {leds[1]}]
set_property PACKAGE_PIN D20 [get_ports {leds[2]}]
set_property PACKAGE_PIN C20 [get_ports {leds[3]}]

set_property PACKAGE_PIN M13 [get_ports {switches[0]}]
set_property PACKAGE_PIN K14 [get_ports {switches[1]}]
set_property PACKAGE_PIN K13 [get_ports {switches[2]}]
set_property PACKAGE_PIN L13 [get_ports {switches[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {switches*}]

set_property PACKAGE_PIN F16 [get_ports {debug[0]}]
# Route to another pin, as we're taking over it for the uart keyboard input
#set_property PACKAGE_PIN F18 [get_ports {debug[1]}]
set_property PACKAGE_PIN E18 [get_ports {debug[1]}]
set_property PACKAGE_PIN E19 [get_ports {debug[2]}]
set_property PACKAGE_PIN D17 [get_ports {debug[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {debug}]

# Temporarily diverted to the auxilary UART
#set_property PACKAGE_PIN G15 [get_ports uart_rx]
set_property PACKAGE_PIN F18 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

set_property PACKAGE_PIN G16 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

set_property PACKAGE_PIN T19 [get_ports spi_cs_n]
# set_property PACKAGE_PIN L12 [get_ports spi_clk]
set_property PACKAGE_PIN P22 [get_ports {spi_dq[0]}]
set_property PACKAGE_PIN R22 [get_ports {spi_dq[1]}]
set_property PACKAGE_PIN P21 [get_ports {spi_dq[2]}]
set_property PACKAGE_PIN R21 [get_ports {spi_dq[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports spi_*]

############ Numeric display ############
set_property PACKAGE_PIN H4 [get_ports {numeric_segments_n[0]}]
set_property PACKAGE_PIN K3 [get_ports {numeric_segments_n[1]}]
set_property PACKAGE_PIN K6 [get_ports {numeric_segments_n[2]}]
set_property PACKAGE_PIN G4 [get_ports {numeric_segments_n[3]}]
set_property PACKAGE_PIN H5 [get_ports {numeric_segments_n[4]}]
set_property PACKAGE_PIN J6 [get_ports {numeric_segments_n[5]}]
set_property PACKAGE_PIN M3 [get_ports {numeric_segments_n[6]}]
set_property PACKAGE_PIN J5 [get_ports {numeric_segments_n[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports numeric_segments_n]

set_property PACKAGE_PIN M2 [get_ports {numeric_enable_n[0]}]
set_property PACKAGE_PIN N4 [get_ports {numeric_enable_n[1]}]
set_property PACKAGE_PIN L5 [get_ports {numeric_enable_n[2]}]
set_property PACKAGE_PIN L4 [get_ports {numeric_enable_n[3]}]
set_property PACKAGE_PIN M16 [get_ports {numeric_enable_n[4]}]
set_property PACKAGE_PIN M17 [get_ports {numeric_enable_n[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports numeric_enable_n]

############## NET - IOSTANDARD ##################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]

############# SPI Configurate Setting ##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

set_false_path -from [get_ports switches*]
set_false_path -from [get_ports nReset]
set_false_path -from [get_ports uart_rx]

set_false_path -to [get_ports uart_tx]
set_false_path -to [get_ports leds*]

############ DDR pins not covered by MIG #############
set_property IOSTANDARD SSTL15 [get_ports {ddr3_dm[0]}]
set_property PACKAGE_PIN AB1 [get_ports {ddr3_dm[0]}]

set_property IOSTANDARD SSTL15 [get_ports {ddr3_dm[1]}]
set_property PACKAGE_PIN W2 [get_ports {ddr3_dm[1]}]

############## HDMIOUT #########################
set_property PACKAGE_PIN D1 [get_ports TMDS_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports TMDS_clk_n]

set_property PACKAGE_PIN E1 [get_ports TMDS_clk_p]
set_property IOSTANDARD TMDS_33 [get_ports TMDS_clk_p]

set_property PACKAGE_PIN F1 [get_ports {TMDS_data_n[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[0]}]

set_property PACKAGE_PIN G1 [get_ports {TMDS_data_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[0]}]

set_property PACKAGE_PIN G2 [get_ports {TMDS_data_n[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[1]}]

set_property PACKAGE_PIN H2 [get_ports {TMDS_data_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[1]}]

set_property PACKAGE_PIN J1 [get_ports {TMDS_data_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[2]}]

set_property PACKAGE_PIN K1 [get_ports {TMDS_data_p[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[2]}]

set_property PACKAGE_PIN M6 [get_ports {HDMI_OEN[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {HDMI_OEN[0]}]
