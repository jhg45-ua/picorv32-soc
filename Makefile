# Toolchain and Vivado paths for RHEL 9.8
# If the toolchain isn't found use full path:
# 	- RISC-V GNU Toolchain: /opt/riscv/bin/
# 	- Vivado: /tools/Xilinx/2025.2/Vivado
TOOLCHAIN_PREFIX ?= riscv64-unknown-elf-
VIVADO_BASE      ?= /tools/Xilinx/2025.2/Vivado
VIVADO           ?= vivado
XVLOG            ?= xvlog
XELAB            ?= xelab
GLBL             ?= $(VIVADO_BASE)/data/verilog/src/glbl.v
IVERILOG  		 ?= iverilog
VVP              ?= vvp
VERILATOR        ?= verilator
SURFER           ?= surfer

BUILD_DIR = build
APP	     ?= counter
PORT     ?= /dev/ttyUSB1

help:
	@echo "Available commands:"
	@echo "  make fw     	   - Compile RISC-V firmware to firmware.hex"
	@echo "  make sim    	   - Run behavioral simulation with Vivado xsim"
	@echo "  make sim-iverilog - Run behavioral simulation with Icarus Verilog"
	@echo "  make sim-waves    - Run behavioral simulation with Icarus Verilog and generate waveform.vcd"
	@echo "  make viewer       - Open waveform.vcd in GTKWave"
	@echo "  make synth        - Run non-project batch synthesis & generate system.bit"
	@echo "  make prog         - Program the Nexys A7-100T FPGA over JTAG"
	@echo "  make lint         - Run Verilator linting on the RTL"
	@echo "  make clean        - Remove build artifacts and logs"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# -------------------------------------------------------------
# Bootloader (FPGA initial memory) & User Apps
# -------------------------------------------------------------
# Bootloader link to 0x0 -> goes directly to BRAM at synthesis
fw: firmware.hex

firmware.hex: sw/common/firmware.S sw/bootloader/bootloader.c sw/common/firmware.lds sw/common/io.h $(BUILD_DIR)
	@echo "-----------------------------------------------------------------------------"
	$(TOOLCHAIN_PREFIX)gcc -Os -mabi=ilp32 -march=rv32i -ffreestanding -nostdlib -o $(BUILD_DIR)/bootloader.elf \
		sw/common/firmware.S sw/bootloader/bootloader.c \
		--std=gnu99 -Wl,-Bstatic,-T,sw/common/firmware.lds,--defsym=ORG=0x0,-Map,$(BUILD_DIR)/bootloader.map,--strip-debug -lgcc
	@echo "-----------------------------------------------------------------------------"

	$(TOOLCHAIN_PREFIX)objcopy -O binary $(BUILD_DIR)/bootloader.elf $(BUILD_DIR)/bootloader.bin
	python3 sw/common/makehex.py $(BUILD_DIR)/bootloader.bin 4096 > firmware.hex

# Compile any App from sw/apps/$(APP).c, link to 0x800
app: $(BUILD_DIR)
	@echo "-----------------------------------------------------------------------------"
	$(TOOLCHAIN_PREFIX)gcc -Os -mabi=ilp32 -march=rv32i -ffreestanding -nostdlib -o $(BUILD_DIR)/$(APP).elf \
		sw/common/firmware.S sw/apps/$(APP).c \
		--std=gnu99 -Wl,-Bstatic,-T,sw/common/firmware.lds,--defsym=ORG=0x800,-Map,$(BUILD_DIR)/$(APP).map,--strip-debug -lgcc
	@echo "-----------------------------------------------------------------------------"

	$(TOOLCHAIN_PREFIX)objcopy -O binary $(BUILD_DIR)/$(APP).elf $(BUILD_DIR)/$(APP).bin

# Load App through UART to the FPGA (bootloader must be running)
upload: app
	python3 sw/common/upload.py $(BUILD_DIR)/$(APP).bin $(PORT)

# -------------------------------------------------------------
# RTL Simulation (using Vivado xvlog/xelab)
# -------------------------------------------------------------
sim: firmware.hex
	$(XVLOG) rtl/cores/picorv32.v rtl/periph/simpleuart.v rtl/soc/system.v sim/system_tb.v
	$(XVLOG) $(GLBL)
	$(XELAB) -L unifast_ver -L unisims_ver -R system_tb glbl

# -------------------------------------------------------------
# RTL Simulation (using Icarus Verilog)
# -------------------------------------------------------------
sim-iverilog: firmware.hex $(BUILD_DIR)
	$(IVERILOG) -o $(BUILD_DIR)/simv rtl/cores/picorv32.v rtl/periph/simpleuart.v rtl/soc/system.v sim/system_tb.v
	$(VVP) $(BUILD_DIR)/simv

sim-waves: firmware.hex $(BUILD_DIR)
	$(IVERILOG) -o $(BUILD_DIR)/simv rtl/cores/picorv32.v rtl/periph/simpleuart.v rtl/soc/system.v sim/system_tb.v
	$(VVP) -n $(BUILD_DIR)/simv +vcd

viewer: sim-waves
	$(SURFER) system.vcd

# -------------------------------------------------------------
# FPGA Bitstream Synthesis (using Vivado non-project batch mode)
# -------------------------------------------------------------
synth: firmware.hex $(BUILD_DIR)
	@echo "-----------------------------------------------------------------------------"
	$(VIVADO) -nojournal -log $(BUILD_DIR)/synth.log -mode batch -source boards/nexys_a7_100T/synth_system.tcl
	@echo "-----------------------------------------------------------------------------"

	@echo "Synthesis completed! Bitstream is in $(BUILD_DIR)/system.bit"
	@grep -B2 -A8 "Slice LUTs" $(BUILD_DIR)/utilization.rpt || true

# -------------------------------------------------------------
# FPGA JTAG Programming (using Vivado hw-manager)
# -------------------------------------------------------------
prog:
	$(VIVADO) -nojournal -mode batch -source boards/nexys_a7_100T/prog.tcl

# -------------------------------------------------------------
# Linting (using Verilator)
# -------------------------------------------------------------
lint:
	$(VERILATOR) -sv --lint-only -Wall \
		-y rtl/cores -y rtl/periph -y rtl/soc \
		-Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-BLKSEQ -Wno-DECLFILENAME -Wno-GENUNNAMED -Wno-MULTITOP \
		rtl/soc/system.v

clean:
	rm -rf $(BUILD_DIR) firmware.hex .Xil/ *.jou *.log xsim.dir/ xvlog.* xelab.* webtalk* work.system_tb#work.glbl.wdb system.vcd

.PHONY: help fw sim synth prog clean