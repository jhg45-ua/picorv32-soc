# ANSI color codes for clean messages
CYAN   := \033[1;36m
GREEN  := \033[1;32m
YELLOW := \033[1;33m
RESET  := \033[0m

# Toolchain and Vivado paths for RHEL 9.8
# If the toolchain isn't found use full path:
# 	- RISC-V GNU Toolchain: /opt/riscv/bin/
# 	- Vivado: /tools/Xilinx/2025.2/Vivado
TOOLCHAIN_PREFIX ?= riscv64-unknown-elf-
VIVADO_BASE      ?= /tools/Xilinx/2025.2/Vivado
VIVADO           ?= vivado	#
XVLOG            ?= xvlog	# Vivado simulator compiler
XELAB            ?= xelab	# Vivado simulator elaborator
GLBL             ?= $(VIVADO_BASE)/data/verilog/src/glbl.v
IVERILOG  		 ?= iverilog -g2012
VVP              ?= vvp
VERILATOR        ?= verilator
SURFER           ?= surfer

BUILD_DIR = build
APP	     ?= counter
PORT     ?= /dev/ttyUSB1
TMR      ?= 0
BITSTREAM ?= prebuilt/system$$( [ "$(TMR)" = "1" ] && echo "_tmr" ).bit

help:
	@echo "Available commands:"
	@echo "  make fw     	   - Compile RISC-V firmware to firmware.hex"
	@echo "  make sim    	   - Run behavioral simulation with Vivado xsim"
	@echo "  make sim-iverilog - Run behavioral simulation with Icarus Verilog"
	@echo "  make sim-tmr      - Run simulation with TMR enabled and fault injection test"
	@echo "  make sim-waves    - Run behavioral simulation with Icarus Verilog and generate waveform.vcd"
	@echo "  make viewer       - Open waveform.vcd in GTKWave"
	@echo "  make synth        - Run non-project batch synthesis & generate system.bit"
	@echo "  make synth-tmr    - Run synthesis with TMR enabled & generate system_tmr.bit"
	@echo "  make prog         - Program the Nexys A7-100T FPGA over JTAG (default: system.bit)"
	@echo "  make prog-tmr     - Program the Nexys A7-100T FPGA over JTAG with system_tmr.bit"
	@echo "  make lint         - Run Verilator linting on the RTL"
	@echo "  make clean        - Remove build artifacts and logs"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# -------------------------------------------------------------
# Bootloader (FPGA initial memory) & User Apps
# -------------------------------------------------------------
# Bootloader link to 0x0 -> goes directly to BRAM at synthesis
fw: $(BUILD_DIR)/firmware.hex

$(BUILD_DIR)/firmware.hex: sw/common/firmware.S sw/bootloader/bootloader.c sw/common/firmware.lds sw/common/io.h $(BUILD_DIR)
	@printf "$(CYAN)[CC]$(RESET)     Compiling firmware...\n"

	@$(TOOLCHAIN_PREFIX)gcc -Os -mabi=ilp32 -march=rv32i -ffreestanding -nostdlib -o $(BUILD_DIR)/bootloader.elf \
		sw/common/firmware.S sw/bootloader/bootloader.c \
		--std=gnu99 -Wl,-Bstatic,-T,sw/common/firmware.lds,--defsym=ORG=0x0,-Map,$(BUILD_DIR)/bootloader.map,--strip-debug \
		-lgcc

	@printf "$(GREEN)[HEX]$(RESET)    Generating $@\n"

	@$(TOOLCHAIN_PREFIX)objcopy -O binary $(BUILD_DIR)/bootloader.elf $(BUILD_DIR)/bootloader.bin
	@python3 sw/common/makehex.py $(BUILD_DIR)/bootloader.bin 4096 > $(BUILD_DIR)/firmware.hex

# Compile any App from sw/apps/$(APP).c, link to 0x800
app: $(BUILD_DIR)
	@printf "$(CYAN)[CC]$(RESET)     Compiling $(APP).c -> $(BUILD_DIR)/$(APP).elf\n"

	$(TOOLCHAIN_PREFIX)gcc -Os -mabi=ilp32 -march=rv32i -ffreestanding -nostdlib -o $(BUILD_DIR)/$(APP).elf \
		sw/common/firmware.S sw/apps/$(APP).c \
		--std=gnu99 -Wl,-Bstatic,-T,sw/common/firmware.lds,--defsym=ORG=0x800,-Map,$(BUILD_DIR)/$(APP).map,--strip-debug \
		-lgcc

	@printf "$(GREEN)[BIN]$(RESET)    Generating $(BUILD_DIR)/$(APP).bin\n"

	$(TOOLCHAIN_PREFIX)objcopy -O binary $(BUILD_DIR)/$(APP).elf $(BUILD_DIR)/$(APP).bin

# Load App through UART to the FPGA (bootloader must be running)
upload: app
	python3 sw/common/upload.py $(BUILD_DIR)/$(APP).bin $(PORT)

# -------------------------------------------------------------
# RTL Simulation (using Vivado xvlog/xelab)
# -------------------------------------------------------------
sim: $(BUILD_DIR)/firmware.hex
	$(XVLOG) rtl/common/tmr_voter.v rtl/cores/picorv32.v rtl/periph/simpleuart.v rtl/soc/system.v sim/system_tb.v
	$(XVLOG) $(GLBL)
	$(XELAB) -L unifast_ver -L unisims_ver -R system_tb glbl

# -------------------------------------------------------------
# RTL Simulation (using Icarus Verilog)
# -------------------------------------------------------------
sim-iverilog: $(BUILD_DIR)/firmware.hex $(BUILD_DIR)
	$(IVERILOG) -o $(BUILD_DIR)/simv rtl/common/tmr_voter.v rtl/cores/picorv32.v rtl/periph/simpleuart.v rtl/soc/system.v sim/system_tb.v
	$(VVP) $(BUILD_DIR)/simv

sim-tmr: $(BUILD_DIR)/firmware.hex $(BUILD_DIR)
	$(IVERILOG) -DPICORV32_TMR -o $(BUILD_DIR)/simv_tmr rtl/common/tmr_voter.v rtl/cores/picorv32.v rtl/periph/simpleuart.v rtl/soc/system.v sim/system_tb.v
	$(VVP) $(BUILD_DIR)/simv_tmr

sim-waves: $(BUILD_DIR)/firmware.hex $(BUILD_DIR)
	$(IVERILOG) -o $(BUILD_DIR)/simv rtl/common/tmr_voter.v rtl/cores/picorv32.v rtl/periph/simpleuart.v rtl/soc/system.v sim/system_tb.v
	$(VVP) -n $(BUILD_DIR)/simv +vcd

viewer:
	$(SURFER) system.vcd

# -------------------------------------------------------------
# FPGA Bitstream Synthesis (using Vivado non-project batch mode)
# -------------------------------------------------------------
synth: $(BUILD_DIR)/firmware.hex $(BUILD_DIR)
	@printf "$(YELLOW)[VIVADO]$(RESET) Running synthesis in batch mode (TMR=$(TMR))...\n"

	TMR=$(TMR) $(VIVADO) -nojournal -log $(BUILD_DIR)/synth$$( [ "$(TMR)" = "1" ] && echo "_tmr" ).log -mode batch \
		-source boards/nexys_a7_100T/synth_system.tcl -tclargs TMR=$(TMR)

	@printf "$(GREEN)[OK]$(RESET)     Synthesis completed!\n"
	@if [ "$(TMR)" = "1" ]; then \
		echo "Bitstream is in prebuilt/system_tmr.bit"; \
		grep -B2 -A8 "Slice LUTs" $(BUILD_DIR)/utilization_system_tmr.rpt 2>/dev/null || true; \
	else \
		echo "Bitstream is in prebuilt/system.bit"; \
		grep -B2 -A8 "Slice LUTs" $(BUILD_DIR)/utilization_system.rpt 2>/dev/null || true; \
	fi

synth-tmr:
	@$(MAKE) synth TMR=1

# -------------------------------------------------------------
# FPGA JTAG Programming (using Vivado hw-manager)
# -------------------------------------------------------------
prog:
	BITSTREAM=$(BITSTREAM) $(VIVADO) -nojournal -mode batch -source boards/nexys_a7_100T/prog.tcl

prog-tmr:
	@$(MAKE) prog BITSTREAM=prebuilt/system_tmr.bit

# -------------------------------------------------------------
# Linting (using Verilator)
# -------------------------------------------------------------
lint:
	$(VERILATOR) -sv --lint-only -Wall \
		-y rtl/common -y rtl/cores -y rtl/periph -y rtl/soc \
		-Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-BLKSEQ -Wno-DECLFILENAME -Wno-GENUNNAMED -Wno-MULTITOP \
		rtl/soc/system.v

clean:
	@printf "$(YELLOW)[CLEAN]$(RESET) Removing build artifacts and logs...\n"

	@rm -rf $(BUILD_DIR) .Xil/ *.jou *.log xsim.dir/ xvlog.* xelab.* webtalk* work.system_tb#work.glbl.wdb system.vcd

	@printf "$(GREEN)[OK]$(RESET)     Clean completed!\n"

.PHONY: help fw sim sim-iverilog sim-tmr synth synth-tmr prog prog-tmr lint clean