# PicoRV32 SoC for Nexys A7-100T

Minimal RISC-V (RV32I) System-on-Chip built around the [PicoRV32](https://github.com/YosysHQ/picorv32) core for the **Digilent Nexys A7-100T** (`xc7a100tcsg324-1`) FPGA board. Includes a UART bootloader, memory-mapped peripherals, and optional selective **Triple Modular Redundancy (TMR)** hardening against Single Event Upsets (SEUs).

## Architecture & Memory Map

The SoC (`rtl/soc/system.v`) runs at **100 MHz** and provides 16 KB of BRAM along with memory-mapped I/O:

| Address       | Peripheral           | Description                                                |
| ------------- | -------------------- | ---------------------------------------------------------- |
| `0x0000_0000` | BRAM (16 KB)         | Main memory initialized with `build/firmware.hex`          |
| `0x0000_0800` | `APP_BASE`           | Entry point in RAM for applications loaded via UART        |
| `0x1000_0000` | `REG_LEDS`           | 15-bit user LEDs (`LED[14:0]`). `LED[15]` indicates `trap` |
| `0x2000_0004` | `REG_UART_CLKDIV`    | UART baud rate divider (`868` for 115200 baud @ 100 MHz)   |
| `0x2000_0008` | `REG_UART_DATA`      | UART TX/RX data register (`simpleuart`)                    |

## Selective TMR Hardening

When compiled or synthesized with `PICORV32_TMR` (`TMR=1`), critical control registers inside the core are triplicated (`_a`, `_b`, `_c` with `KEEP` / `DONT_TOUCH` attributes) and resolved through majority voters (`rtl/common/tmr_voter.v`) with self-healing feedback on every clock cycle:

- **Control FSM (`PICORV32_TMR_FSM`)**: Protects `cpu_state` against illegal state transitions.
- **Program Counter (`PICORV32_TMR_PC`)**: Protects `reg_pc` and `reg_next_pc`.
- **Control Path (`PICORV32_TMR_CTRL`)**: Protects the destination register index (`latched_rd`).
- **Memory Bus FSM (`PICORV32_TMR_MEM`)**: Protects `mem_state` during bus transactions.

Each voter also exposes a `*_fault_detected` signal when a discrepancy occurs between branches.

## Project Structure

```text
├── boards/nexys_a7_100T/   # Vivado XDC constraints and batch TCL scripts
├── prebuilt/               # Generated bitstreams (system.bit / system_tmr.bit)
├── rtl/
│   ├── common/tmr_voter.v  # Parameterizable majority voter + fault detector
│   ├── cores/picorv32.v    # PicoRV32 core with selective TMR macros
│   ├── periph/simpleuart.v # UART peripheral
│   └── soc/system.v        # Top-level SoC integration and MMIO bus
├── sim/system_tb.v         # Testbench with UART decoder and SEU fault injection
└── sw/
    ├── apps/counter.c      # Sample LED counter + UART heartbeat app
    ├── bootloader/         # UART bootloader (self-test + binary loader to 0x800)
    └── common/             # Startup code, linker script, MMIO header, and Python tools
```

## Dependencies

- **RISC-V Toolchain**: `riscv64-unknown-elf-gcc`
- **Simulation & Linting**: `iverilog`, `vvp`, `verilator`, and optionally `surfer`
- **Synthesis & Flashing**: Xilinx `vivado` (batch mode) or `openFPGALoader`
- **Python 3**: `pyserial` (for `sw/common/upload.py`)

## Usage

### 1. Firmware & Bootloader

The base firmware loaded into BRAM at `0x0` is controlled by `FW_SRC` in the `Makefile`:

```bash
# Compile default base firmware (counter.c or bootloader.c)
make fw

# Or specify the source file explicitly
make fw FW_SRC=sw/bootloader/bootloader.c
```

To compile an application to be loaded into RAM (`0x800`) by the UART bootloader:

```bash
make app APP=counter
make upload APP=counter PORT=/dev/ttyUSB1
```

When `make upload` is waiting, press the red `CPU_RESETN` button on the board so the bootloader runs its self-test, sends `READY`, and jumps to the uploaded binary.

### 2. Simulation

```bash
# Standard RTL simulation
make sim

# TMR simulation with automated SEU fault injection tests
make sim-tmr

# Run simulation and open waveforms in Surfer
make sim-waves
```

### 3. FPGA Synthesis & Programming

```bash
# Synthesize standard bitstream (prebuilt/system.bit)
make synth

# Synthesize TMR-hardened bitstream (prebuilt/system_tmr.bit)
make synth-tmr

# Program board using Vivado JTAG (add TMR=1 for the TMR bitstream)
make prog

# Program board using openFPGALoader (without Vivado)
make prog-ofl
make prog-ofl-tmr
```

### 4. Linting & Cleanup

```bash
make lint
make clean
```

## License

MIT
