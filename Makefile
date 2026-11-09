# -------------------------------------------------------------
# Config and Tools
# -------------------------------------------------------------
TOOLCHAIN ?= riscv64-unknown-elf-
VIVADO    ?= vivado
IVERILOG  ?= iverilog -g2012
VVP       ?= vvp
VERILATOR ?= verilator
OFL       ?= openFPGALoader -b nexys_a7_100

BUILD_DIR ?= build
PORT      ?= /dev/ttyUSB1
APP       ?= counter

# Source file C for base firmware (initialized in BRAM in 0x0)
# Change this variable to compile another app as base firmware:
# ex: FW_SRC ?= sw/bootloader/bootloader.c
FW_SRC    ?= sw/apps/counter.c

# Hardening modes (0: disabled, 1: enabled)
TMR         ?= 0
ECC         ?= 0
MODE_SUFFIX := $(if $(filter 1,$(TMR)),_tmr,)$(if $(filter 1,$(ECC)),_ecc,)
BITSTREAM   ?= prebuilt/system$(MODE_SUFFIX).bit

# RTL sources (common, cores, peripherals, SoC)
RTL_SRCS   := rtl/common/tmr_voter.v rtl/common/ecc_secded32_enc.v rtl/common/ecc_secded32_dec.v rtl/cores/picorv32.v rtl/periph/simpleuart.v rtl/soc/bram_ecc.v rtl/soc/system.v
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
	@echo "  make fw               - Compile base firmware (firmware.hex and firmware.coe)"
	@echo "  make app              - Compile app (ex: make app APP=counter)"
	@echo "  make upload           - Upload app via UART to the board"
	@echo "  make sim              - Simulate standard SoC (Icarus Verilog)"
	@echo "  make sim-tmr          - Simulate with TMR control hardening & fault injection"
	@echo "  make sim-ecc          - Simulate with ECC memory hardening & fault injection"
	@echo "  make sim-tmr-ecc      - Simulate with full TMR + ECC protection"
	@echo "  make sim-ecc-unit     - Run unit tests for ECC (SECDED & picorv32_regs)"
	@echo "  make sim-waves        - Simulate and open waves in Surfer/GTKWave"
	@echo "  make synth            - Synthesize standard bitstream (system.bit)"
	@echo "  make synth-tmr        - Synthesize with TMR hardening (system_tmr.bit)"
	@echo "  make synth-ecc        - Synthesize with ECC memory hardening (system_ecc.bit)"
	@echo "  make synth-tmr-ecc    - Synthesize with full TMR + ECC (system_tmr_ecc.bit)"
	@echo "  make prog             - Flash standard bitstream via Vivado JTAG"
	@echo "  make prog-tmr         - Flash TMR bitstream via Vivado JTAG"
	@echo "  make prog-ecc         - Flash ECC bitstream via Vivado JTAG"
	@echo "  make prog-tmr-ecc     - Flash full TMR+ECC bitstream via Vivado JTAG"
	@echo "  make prog-ofl         - Flash standard bitstream with openFPGALoader"
	@echo "  make prog-ofl-tmr     - Flash TMR bitstream with openFPGALoader"
	@echo "  make prog-ofl-ecc     - Flash ECC bitstream with openFPGALoader"
	@echo "  make prog-ofl-tmr-ecc - Flash full TMR+ECC bitstream with openFPGALoader"
	@echo "  make lint             - Linting RTL with Verilator"
	@echo "  make clean            - Clean build folder and temporary files"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# -------------------------------------------------------------
# Firmware RISC-V
# -------------------------------------------------------------
fw:
	@rm -f $(BUILD_DIR)/firmware.hex
	@$(MAKE) $(BUILD_DIR)/firmware.hex FW_SRC="$(FW_SRC)"

$(BUILD_DIR)/firmware.hex: sw/common/firmware.S $(FW_SRC) sw/common/firmware.lds Makefile | $(BUILD_DIR)
	@echo "[CC] Compiling $(FW_SRC) as base firmware (ORG=0x0)..."
	@$(TOOLCHAIN)gcc $(CFLAGS) sw/common/firmware.S $(FW_SRC) \
		$(LDFLAGS),--defsym=ORG=0x0,-Map,$(BUILD_DIR)/firmware.map $(LIBS) -o $(BUILD_DIR)/firmware.elf
	@$(TOOLCHAIN)objcopy -O binary $(BUILD_DIR)/firmware.elf $(BUILD_DIR)/firmware.bin
	@python3 sw/common/makehex.py $(BUILD_DIR)/firmware.bin 4096 $(BUILD_DIR)/firmware.coe > $@
	@echo "[OK] Firmware generated in $@ and $(BUILD_DIR)/firmware.coe"

app: $(BUILD_DIR)
	@echo "[CC] Compiling $(APP).c..."
	@$(TOOLCHAIN)gcc $(CFLAGS) sw/common/firmware.S sw/apps/$(APP).c \
		$(LDFLAGS),--defsym=ORG=0x800,-Map,$(BUILD_DIR)/$(APP).map $(LIBS) -o $(BUILD_DIR)/$(APP).elf
	@$(TOOLCHAIN)objcopy -O binary $(BUILD_DIR)/$(APP).elf $(BUILD_DIR)/$(APP).bin

upload: app
	python3 sw/common/upload.py $(BUILD_DIR)/$(APP).bin $(PORT)

# -------------------------------------------------------------
# RTL Simulation (Icarus Verilog)
# -------------------------------------------------------------
sim: fw
	$(IVERILOG) -o $(BUILD_DIR)/simv $(RTL_SRCS) $(TB_SRCS)
	$(VVP) $(BUILD_DIR)/simv

sim-tmr: fw
	$(IVERILOG) -DPICORV32_TMR -o $(BUILD_DIR)/simv_tmr $(RTL_SRCS) $(TB_SRCS)
	$(VVP) $(BUILD_DIR)/simv_tmr

sim-ecc: fw
	$(IVERILOG) -DPICORV32_ECC -o $(BUILD_DIR)/simv_ecc $(RTL_SRCS) $(TB_SRCS)
	$(VVP) $(BUILD_DIR)/simv_ecc

sim-tmr-ecc: fw
	$(IVERILOG) -DPICORV32_TMR -DPICORV32_ECC -o $(BUILD_DIR)/simv_tmr_ecc $(RTL_SRCS) $(TB_SRCS)
	$(VVP) $(BUILD_DIR)/simv_tmr_ecc

sim-ecc-unit: $(BUILD_DIR)
	$(IVERILOG) -o $(BUILD_DIR)/ecc_secded32_tb.vvp rtl/common/ecc_secded32_enc.v rtl/common/ecc_secded32_dec.v sim/ecc_secded32_tb.v
	$(VVP) $(BUILD_DIR)/ecc_secded32_tb.vvp
	$(IVERILOG) -DPICORV32_ECC -o $(BUILD_DIR)/picorv32_regs_tb.vvp rtl/common/ecc_secded32_enc.v rtl/common/ecc_secded32_dec.v rtl/cores/picorv32.v sim/picorv32_regs_tb.v
	$(VVP) $(BUILD_DIR)/picorv32_regs_tb.vvp

sim-waves: fw
	$(IVERILOG) -o $(BUILD_DIR)/simv $(RTL_SRCS) $(TB_SRCS)
	$(VVP) -n $(BUILD_DIR)/simv +vcd
	surfer system.vcd

# -------------------------------------------------------------
# Synth Vivado (Batch mode)
# -------------------------------------------------------------
synth: fw
	@echo "[VIVADO] Synthesizing (TMR=$(TMR) ECC=$(ECC))..."
	@TMR=$(TMR) ECC=$(ECC) $(VIVADO) -nojournal -log $(BUILD_DIR)/synth$(MODE_SUFFIX).log -mode batch \
		-source boards/nexys_a7_100T/synth_system.tcl -tclargs TMR=$(TMR) ECC=$(ECC)
	@echo "[OK] Bitstream generated in $(BITSTREAM)"
	@grep -B2 -A8 "Slice LUTs" $(BUILD_DIR)/utilization_system$(MODE_SUFFIX).rpt 2>/dev/null || true

synth-tmr:
	@$(MAKE) synth TMR=1 ECC=0

synth-ecc:
	@$(MAKE) synth TMR=0 ECC=1

synth-tmr-ecc:
	@$(MAKE) synth TMR=1 ECC=1

# -------------------------------------------------------------
# Flash / JTAG
# -------------------------------------------------------------
prog:
	BITSTREAM=$(BITSTREAM) $(VIVADO) -nojournal -mode batch -source boards/nexys_a7_100T/prog.tcl

prog-tmr:
	@$(MAKE) prog TMR=1 ECC=0

prog-ecc:
	@$(MAKE) prog TMR=0 ECC=1

prog-tmr-ecc:
	@$(MAKE) prog TMR=1 ECC=1

prog-ofl:
	$(OFL) $(BITSTREAM)

prog-ofl-tmr:
	@$(MAKE) prog-ofl TMR=1 ECC=0

prog-ofl-ecc:
	@$(MAKE) prog-ofl TMR=0 ECC=1

prog-ofl-tmr-ecc:
	@$(MAKE) prog-ofl TMR=1 ECC=1

# -------------------------------------------------------------
# Linting RTL (Verilator) & Cleaning
# -------------------------------------------------------------
lint:
	$(VERILATOR) -sv --lint-only -Wall -y rtl/common -y rtl/cores -y rtl/periph -y rtl/soc \
		-Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-BLKSEQ -Wno-DECLFILENAME -Wno-GENUNNAMED -Wno-MULTITOP \
		-Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-TIMESCALEMOD -Wno-PROCASSINIT -Wno-PINMISSING -Wno-UNUSEDPARAM \
		rtl/soc/system.v

clean:
	@rm -rf $(BUILD_DIR) blk_mem_gen_ecc .Xil/ *.jou *.log xsim.dir/ xvlog.* xelab.* webtalk* *.vcd
	@echo "[OK] Directory cleaned."

.PHONY: help fw app upload sim sim-tmr sim-ecc sim-tmr-ecc sim-ecc-unit sim-waves \
	synth synth-tmr synth-ecc synth-tmr-ecc \
	prog prog-tmr prog-ecc prog-tmr-ecc \
	prog-ofl prog-ofl-tmr prog-ofl-ecc prog-ofl-tmr-ecc \
	lint clean