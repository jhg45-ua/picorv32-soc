# -------------------------------------------------------------
# Vivado Synthesis Script for PicoRV32 SoC (Nexys A7-100T)
# Supports: Standard, TMR only, ECC only, and TMR+ECC
# -------------------------------------------------------------

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

# Check if ECC is enabled via environment variable or TCL argument
set enable_ecc 0
if {[info exists env(ECC)] && $env(ECC) == "1"} {
    set enable_ecc 1
}
foreach arg $argv {
    if {$arg eq "ECC" || $arg eq "ECC=1" || $arg eq "PICORV32_ECC"} {
        set enable_ecc 1
    }
}

# Determine target name and banner
set bit_suffix ""
if {$enable_tmr} {
    set bit_suffix "${bit_suffix}_tmr"
}
if {$enable_ecc} {
    set bit_suffix "${bit_suffix}_ecc"
}
set bit_name "system${bit_suffix}"

puts "\n============================================================="
if {$enable_tmr && $enable_ecc} {
    puts "  BUILD TARGET: FULL HARDENING (TMR Control + ECC Memories)  "
} elseif {$enable_tmr} {
    puts "  BUILD TARGET: PICORV32 WITH TMR HARDENING (Control Path)   "
} elseif {$enable_ecc} {
    puts "  BUILD TARGET: PICORV32 WITH ECC HARDENING (Memories)       "
} else {
    puts "  BUILD TARGET: STANDARD PICORV32 (No Hardening)             "
}
puts "  OUTPUT BITSTREAM: prebuilt/${bit_name}.bit"
puts "=============================================================\n"

# Read Verilog RTL sources
read_verilog rtl/common/tmr_voter.v
read_verilog rtl/common/ecc_secded32_enc.v
read_verilog rtl/common/ecc_secded32_dec.v
read_verilog rtl/cores/picorv32.v
read_verilog rtl/periph/simpleuart.v
read_verilog rtl/soc/bram_ecc.v
read_verilog rtl/soc/system.v

# Read board pin constraints
read_xdc boards/nexys_a7_100T/nexys_a7.xdc

# If ECC is enabled, generate Xilinx Block Memory Generator IP on-the-fly
if {$enable_ecc} {
    puts "--> Generating Xilinx Block Memory Generator IP with Soft ECC..."
    if {![file exists "build/firmware.coe"]} {
        error "ERROR: build/firmware.coe not found! Please run 'make fw' first to generate it."
    }

    create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name blk_mem_gen_ecc
    set_property -dict [list \
        CONFIG.Memory_Type {Simple_Dual_Port_RAM} \
        CONFIG.Assume_Synchronous_Clk {true} \
        CONFIG.Write_Width_A {32} \
        CONFIG.Write_Depth_A {4096} \
        CONFIG.Read_Width_B {32} \
        CONFIG.Enable_B {Use_ENB_Pin} \
        CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
        CONFIG.Use_ECC_Type {Soft_ECC} \
        CONFIG.ECC {true} \
        CONFIG.Error_Injection_Type {Single_Bit_and_Double_Bit_Error_Injection} \
        CONFIG.Use_Error_Injection_Pins {true} \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File [file normalize "build/firmware.coe"] \
    ] [get_ips blk_mem_gen_ecc]
    generate_target synthesis [get_ips blk_mem_gen_ecc]
    catch {synth_ip [get_ips blk_mem_gen_ecc]}
}

# Assemble Verilog defines
set verilog_defines [list]
if {$enable_tmr} {
    lappend verilog_defines "PICORV32_TMR"
}
if {$enable_ecc} {
    lappend verilog_defines "PICORV32_ECC"
    lappend verilog_defines "XILINX_ECC_IP"
}

# Run synthesis targeting Nexys A7-100T
if {[llength $verilog_defines] > 0} {
    puts "--> Running synth_design with defines: $verilog_defines"
    synth_design -part xc7a100tcsg324-1 -top system -verilog_define $verilog_defines
} else {
    puts "--> Running synth_design without additional defines"
    synth_design -part xc7a100tcsg324-1 -top system
}

opt_design
place_design
route_design

# Utilization and timing summaries
file mkdir build
file mkdir reports
report_utilization -file build/utilization_${bit_name}.rpt
report_timing_summary -file build/timing_summary_${bit_name}.rpt
file copy -force build/utilization_${bit_name}.rpt reports/utilization_${bit_name}.rpt
file copy -force build/timing_summary_${bit_name}.rpt reports/timing_summary_${bit_name}.rpt

# Generate compressed bitstream in prebuilt/
file mkdir prebuilt
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
write_bitstream -force prebuilt/${bit_name}.bit
puts "\n\[OK\] Bitstream and reports generated successfully for ${bit_name}."
