# Read Verilog RTL sources
read_verilog rtl/cores/picorv32.v
read_verilog rtl/periph/simpleuart.v
read_verilog rtl/soc/system.v

# Read board pin constraints
read_xdc boards/nexys_a7_100T/nexys_a7.xdc

# Run synthesis targeting Nexys A7-100T
synth_design -part xc7a100tcsg324-1 -top system
opt_design
place_design
route_design

# Utilization and timing summaries
report_utilization -file build/utilization.rpt
report_timing_summary -file build/timing_summary.rpt

# Generate bitstream
write_bitstream -force build/system.bit