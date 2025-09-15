onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /Testbench/DUT/S
add wave -noupdate /Testbench/DUT/C
add wave -noupdate /Testbench/DUT/Vcc
add wave -noupdate /Testbench/DUT/HOLD_DQ3
add wave -noupdate /Testbench/DUT/Vpp_W_DQ2
add wave -noupdate /Testbench/DUT/DQ1
add wave -noupdate /Testbench/DUT/DQ0
add wave -noupdate /Testbench/DUT/any_die_busy
add wave -noupdate /Testbench/DUT/current_die_busy
add wave -noupdate /Testbench/DUT/current_die_active
add wave -noupdate -radix ascii /Testbench/DUT/N25Q_die0/cmdRecName
add wave -noupdate -radix hexadecimal /Testbench/DUT/N25Q_die0/ck_count
add wave -noupdate -radix ascii /Testbench/DUT/N25Q_die0/protocol
add wave -noupdate -radix ascii /Testbench/DUT/N25Q_die0/prog/oldOperation
add wave -noupdate -radix ascii /Testbench/DUT/N25Q_die0/prog/operation
add wave -noupdate /Testbench/DUT/N25Q_die0/prog/d0
add wave -noupdate /Testbench/DUT/N25Q_die0/prog/d1
add wave -noupdate /Testbench/DUT/N25Q_die0/prog/d2
add wave -noupdate -radix ascii /Testbench/DUT/N25Q_die1/cmdRecName
add wave -noupdate -radix hexadecimal /Testbench/DUT/N25Q_die1/ck_count
add wave -noupdate -radix ascii /Testbench/DUT/N25Q_die1/protocol
add wave -noupdate -radix ascii /Testbench/DUT/N25Q_die1/prog/oldOperation
add wave -noupdate -radix ascii /Testbench/DUT/N25Q_die1/prog/operation
add wave -noupdate /Testbench/DUT/N25Q_die1/prog/d0
add wave -noupdate /Testbench/DUT/N25Q_die1/prog/d1
add wave -noupdate /Testbench/DUT/N25Q_die1/prog/d2
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {23470000000 fs} 0}
configure wave -namecolwidth 284
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 3
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {23205063713 fs} {23743731760 fs}
