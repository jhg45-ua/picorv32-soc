# -------------------------------------------------------------
# Config and Tools
# -------------------------------------------------------------
TOOLCHAIN ?= riscv64-unknown-elf-
VIVADO    ?= vivado
IVERILOG  ?= iverilog -g2012
VVP       ?= vvp
VERILATOR ?= verilator
OFL       ?= openFPGALoader -b nexysA7100t

BUILD_DIR ?= build
PORT      ?= /dev/ttyUSB1
APP       ?= counter

# TMR mode (0: standard, 1: triplicated)
TMR        ?= 0
TMR_SUFFIX := $(if $(filter 1,$(TMR)),_tmr,)
BITSTREAM  ?= prebuilt/system$(TMR_SUFFIX).bit

# RTL sources (common, cores, peripherals, SoC)
RTL_SRCS   := rtl/common/tmr_voter.v rtl/cores/picorv32.v rtl/periph/simpleuart.v rtl/soc/system.v
TB_SRCS    := sim/system_tb.v

# Flags RISC-V GCC
CFLAGS     := -Os -mabi=ilp32 -march=rv32i -ffreestanding -nostdlib --std=gnu99
LDFLAGS    := -Wl,-Bstatic,-T,sw/common/firmware.lds,--strip-debug
LIBS       := -lgcc

# -------------------------------------------------------------
# Help
# -------------------------------------------------------------
help:
	@echo "Available commands:"
	@echo "  make fw          - Compile firmware bootloader (firmware.hex)"
	@echo "  make app         - Compile app (ej: make app APP=counter)"
	@echo "  make upload      - Upload app via UART to the board"
	@echo "  make sim         - Simulate SoC (Icarus Verilog)"
	@echo "  make sim-tmr     - Simulate with TMR and fault injection tests"
	@echo "  make sim-waves   - Simulate and open waves in Surfer/GTKWave"
	@echo "  make synth       - Synthesize standard bitstream (prebuilt/system.bit)"
	@echo "  make synth-tmr   - Synthesize with TMR (prebuilt/system_tmr.bit)"
	@echo "  make prog        - Flash with Vivado JTAG"
	@echo "  make prog-ofl    - Flash with openFPGALoader (laptop without Vivado)"
	@echo "  make lint        - Linting RTL with Verilator"
	@echo "  make clean       - Clean build folder and temporary files"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# -------------------------------------------------------------
# Firmware RISC-V
# -------------------------------------------------------------
fw: $(BUILD_DIR)/firmware.hex

$(BUILD_DIR)/firmware.hex: sw/common/firmware.S sw/bootloader/bootloader.c sw/common/firmware.lds $(BUILD_DIR)
	@echo "[CC] Compilando bootloader..."
	@$(TOOLCHAIN)gcc $(CFLAGS) sw/common/firmware.S sw/bootloader/bootloader.c \
		$(LDFLAGS),--defsym=ORG=0x0,-Map,$(BUILD_DIR)/bootloader.map $(LIBS) -o $(BUILD_DIR)/bootloader.elf
	@$(TOOLCHAIN)objcopy -O binary $(BUILD_DIR)/bootloader.elf $(BUILD_DIR)/bootloader.bin
	@python3 sw/common/makehex.py $(BUILD_DIR)/bootloader.bin 4096 > $@

app: $(BUILD_DIR)
	@echo "[CC] Compilando $(APP).c..."
	@$(TOOLCHAIN)gcc $(CFLAGS) sw/common/firmware.S sw/apps/$(APP).c \
		$(LDFLAGS),--defsym=ORG=0x800,-Map,$(BUILD_DIR)/$(APP).map $(LIBS) -o $(BUILD_DIR)/$(APP).elf
	@$(TOOLCHAIN)objcopy -O binary $(BUILD_DIR)/$(APP).elf $(BUILD_DIR)/$(APP).bin

upload: app
	python3 sw/common/upload.py $(BUILD_DIR)/$(APP).bin $(PORT)

# -------------------------------------------------------------
# RTL Simulation (Icarus Verilog)
# -------------------------------------------------------------
sim: $(BUILD_DIR)/firmware.hex $(BUILD_DIR)
	$(IVERILOG) -o $(BUILD_DIR)/simv $(RTL_SRCS) $(TB_SRCS)
	$(VVP) $(BUILD_DIR)/simv

sim-tmr: $(BUILD_DIR)/firmware.hex $(BUILD_DIR)
	$(IVERILOG) -DPICORV32_TMR -o $(BUILD_DIR)/simv_tmr $(RTL_SRCS) $(TB_SRCS)
	$(VVP) $(BUILD_DIR)/simv_tmr

sim-waves: $(BUILD_DIR)/firmware.hex $(BUILD_DIR)
	$(IVERILOG) -o $(BUILD_DIR)/simv $(RTL_SRCS) $(TB_SRCS)
	$(VVP) -n $(BUILD_DIR)/simv +vcd
	surfer system.vcd

# -------------------------------------------------------------
# Synth Vivado (Batch mode)
# -------------------------------------------------------------
synth: $(BUILD_DIR)/firmware.hex $(BUILD_DIR)
	@echo "[VIVADO] Sintetizando (TMR=$(TMR))..."
	@TMR=$(TMR) $(VIVADO) -nojournal -log $(BUILD_DIR)/synth$(TMR_SUFFIX).log -mode batch \
		-source boards/nexys_a7_100T/synth_system.tcl -tclargs TMR=$(TMR)
	@echo "[OK] Bitstream generado en $(BITSTREAM)"
	@grep -B2 -A8 "Slice LUTs" $(BUILD_DIR)/utilization_system$(TMR_SUFFIX).rpt 2>/dev/null || true

synth-tmr:
	@$(MAKE) synth TMR=1

# -------------------------------------------------------------
# Flash / JTAG
# -------------------------------------------------------------
prog:
	BITSTREAM=$(BITSTREAM) $(VIVADO) -nojournal -mode batch -source boards/nexys_a7_100T/prog.tcl

prog-tmr:
	@$(MAKE) prog TMR=1

prog-ofl:
	$(OFL) $(BITSTREAM)

prog-ofl-tmr:
	@$(MAKE) prog-ofl TMR=1

# -------------------------------------------------------------
# Linting RTL (Verilator) & Cleaning
# -------------------------------------------------------------
lint:
	$(VERILATOR) -sv --lint-only -Wall -y rtl/common -y rtl/cores -y rtl/periph -y rtl/soc \
		-Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-BLKSEQ -Wno-DECLFILENAME -Wno-GENUNNAMED -Wno-MULTITOP \
		rtl/soc/system.v

clean:
	@rm -rf $(BUILD_DIR) .Xil/ *.jou *.log xsim.dir/ xvlog.* xelab.* webtalk* *.vcd
	@echo "[OK] Directorio limpio."

.PHONY: help fw app upload sim sim-tmr sim-waves synth synth-tmr prog prog-tmr prog-ofl prog-ofl-tmr lint clean