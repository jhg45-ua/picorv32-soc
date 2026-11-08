# Check if TMR is enabled via environment variable or TCL argument
set enable_tmr 0
if {[info exists env(TMR)] && $env(TMR) == "1"} {
    set enable_tmr 1
}
foreach arg $argv {
    if {$arg eq "TMR" || $arg eq "TMR=1" || $arg eq "PICORV32_TMR"} {
        set enable_tmr 1
    }
}

set bit_name "system"
if {$enable_tmr} {
    set bit_name "system_tmr"
    puts "\n============================================="
    puts "  BUILD TARGET: PICORV32 WITH TMR HARDENING  "
    puts "=============================================\n"
} else {
    puts "\n============================================="
    puts "  BUILD TARGET: STANDARD PICORV32 (NO TMR)   "
    puts "=============================================\n"
}

# Read Verilog RTL sources
read_verilog rtl/common/tmr_voter.v
read_verilog rtl/cores/picorv32.v
read_verilog rtl/periph/simpleuart.v
read_verilog rtl/soc/system.v

# Read board pin constraints
read_xdc boards/nexys_a7_100T/nexys_a7.xdc

# Run synthesis targeting Nexys A7-100T
if {$enable_tmr} {
    synth_design -part xc7a100tcsg324-1 -top system -verilog_define {PICORV32_TMR}
} else {
    synth_design -part xc7a100tcsg324-1 -top system
}
opt_design
place_design
route_design

# Utilization and timing summaries
file mkdir build
report_utilization -file build/utilization_${bit_name}.rpt
report_timing_summary -file build/timing_summary_${bit_name}.rpt

# Generate compressed bitstream in prebuilt/
file mkdir prebuilt
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
write_bitstream -force prebuilt/${bit_name}.bit