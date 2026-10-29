# Toolchain and Vivado paths for RHEL 9.8
TOOLCHAIN_PREFIX ?= /opt/riscv/bin/riscv64-unknown-elf-
VIVADO_BASE      ?= /tools/Xilinx/2025.2/Vivado
VIVADO           ?= $(VIVADO_BASE)/bin/vivado
XVLOG            ?= $(VIVADO_BASE)/bin/xvlog
XELAB            ?= $(VIVADO_BASE)/bin/xelab
GLBL             ?= $(VIVADO_BASE)/data/verilog/src/glbl.v

BUILD_DIR = build

help:
	@echo "Available commands:"
	@echo "  make fw     - Compile RISC-V firmware to firmware.hex"
	@echo "  make sim    - Run behavioral simulation with Vivado xsim"
	@echo "  make synth  - Run non-project batch synthesis & generate system.bit"
	@echo "  make prog   - Program the Nexys A7-100T FPGA over JTAG"
	@echo "  make clean  - Remove build artifacts and logs"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# -------------------------------------------------------------
# 1. Firmware Compilation
# -------------------------------------------------------------
fw: firmware.hex

firmware.hex: sw/common/firmware.S sw/common/firmware.c sw/common/firmware.lds $(BUILD_DIR)
	$(TOOLCHAIN_PREFIX)gcc -Os -mabi=ilp32 -march=rv32i -ffreestanding -nostdlib -o $(BUILD_DIR)/firmware.elf \
		sw/common/firmware.S sw/common/firmware.c \
		--std=gnu99 -Wl,-Bstatic,-T,sw/common/firmware.lds,-Map,$(BUILD_DIR)/firmware.map,--strip-debug -lgcc
	$(TOOLCHAIN_PREFIX)objcopy -O binary $(BUILD_DIR)/firmware.elf $(BUILD_DIR)/firmware.bin
	python3 sw/common/makehex.py $(BUILD_DIR)/firmware.bin 4096 > firmware.hex

# -------------------------------------------------------------
# 2. RTL Simulation (using Vivado xvlog/xelab)
# -------------------------------------------------------------
sim: firmware.hex
	$(XVLOG) rtl/cores/picorv32.v rtl/periph/simpleuart.v rtl/soc/system.v sim/system_tb.v
	$(XVLOG) $(GLBL)
	$(XELAB) -L unifast_ver -L unisims_ver -R system_tb glbl

# -------------------------------------------------------------
# 3. FPGA Bitstream Synthesis
# -------------------------------------------------------------
synth: firmware.hex $(BUILD_DIR)
	$(VIVADO) -nojournal -log $(BUILD_DIR)/synth.log -mode batch -source boards/nexys_a7_100T/synth_system.tcl
	@echo "Synthesis completed! Bitstream is in $(BUILD_DIR)/system.bit"
	@grep -B2 -A8 "Slice LUTs" $(BUILD_DIR)/utilization.rpt || true

# -------------------------------------------------------------
# 4. FPGA JTAG Programming
# -------------------------------------------------------------
prog:
	$(VIVADO) -nojournal -mode batch -source boards/nexys_a7_100T/prog.tcl

clean:
	rm -rf $(BUILD_DIR) firmware.hex .Xil/ *.jou *.log xsim.dir/ xvlog.* xelab.* webtalk*

.PHONY: help fw sim synth prog clean