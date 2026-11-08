`timescale 1 ns / 1 ps

module system #(
    parameter integer MEM_SIZE = 4096,
    parameter FIRMWARE_FILE = "build/firmware.hex"
) (
    input             clk,     // 100 MHz oscillator from Nexys A7 (E3)
    input             resetn,  // CPU_RESETN red push button (C12, active-low)
    output            trap,    // High if CPU executes illegal insn -> LED[15]
    output reg [14:0] leds,    // Lower 15 user LEDs -> LED[14:0]
    output            ser_tx,  // UART TX -> FTDI RX (D4)
    input             ser_rx   // UART RX <- FTDI TX (C4)
);

  // Power-on reset generator
  reg [5:0] reset_cnt = 0;
  wire sys_resetn = &reset_cnt;

  always @(posedge clk) begin
    if (!resetn) reset_cnt <= 0;
    else if (!sys_resetn) reset_cnt <= reset_cnt + 1;
  end

  // Memory bus wires
  wire        mem_valid;
  wire        mem_instr;
  reg         mem_ready;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [ 3:0] mem_wstrb;
  reg  [31:0] mem_rdata;

  // CPU core
  picorv32 #(
      .ENABLE_COUNTERS     (1),
      .ENABLE_COUNTERS64   (0),
      .ENABLE_REGS_16_31   (1),
      .ENABLE_REGS_DUALPORT(1),
      .TWO_STAGE_SHIFT     (1),
      .BARREL_SHIFTER      (1),
      .COMPRESSED_ISA      (0),
      .CATCH_MISALIGN      (1),
      .CATCH_ILLINSN       (1),
      .REGS_INIT_ZERO      (1)
  ) cpu (
      .clk         (clk),
      .resetn      (sys_resetn),
      .trap        (trap),
      .mem_valid   (mem_valid),
      .mem_instr   (mem_instr),
      .mem_ready   (mem_ready),
      .mem_addr    (mem_addr),
      .mem_wdata   (mem_wdata),
      .mem_wstrb   (mem_wstrb),
      .mem_rdata   (mem_rdata),
      .mem_la_read (),
      .mem_la_write(),
      .mem_la_addr (),
      .mem_la_wdata(),
      .mem_la_wstrb(),
      .pcpi_valid  (),
      .pcpi_insn   (),
      .pcpi_rs1    (),
      .pcpi_rs2    (),
      .pcpi_wr     (1'b0),
      .pcpi_rd     (32'h0),
      .pcpi_wait   (1'b0),
      .pcpi_ready  (1'b0),
      .irq         (32'h0),
      .eoi         ()
  );

`ifdef PICORV32_ECC
  // =============================================================
  // Memoria BRAM de 16 KB con Protección ECC SECDED(39,32)
  // =============================================================
  wire        ram_sel = mem_valid && ((mem_addr >> 2) < MEM_SIZE);

  // Registro de estado para Read-Modify-Write (sb, sh)
  reg         rmw_state;

  wire [11:0] bram_addrb = mem_addr[13:2];
  wire        bram_enb   = ram_sel && (!mem_wstrb || ((mem_wstrb != 4'b1111) && !rmw_state));

  wire [31:0] bram_doutb;
  wire        bram_sbiterr;
  wire        bram_dbiterr;
  wire [11:0] bram_rdaddrecc;

  // Multiplexor de fusión: mezcla los bytes nuevos con los 32b sanos leídos de BRAM
  wire [31:0] rmw_merged_data;
  assign rmw_merged_data[7:0]   = mem_wstrb[0] ? mem_wdata[7:0] : bram_doutb[7:0];
  assign rmw_merged_data[15:8]  = mem_wstrb[1] ? mem_wdata[15:8] : bram_doutb[15:8];
  assign rmw_merged_data[23:16] = mem_wstrb[2] ? mem_wdata[23:16] : bram_doutb[23:16];
  assign rmw_merged_data[31:24] = mem_wstrb[3] ? mem_wdata[31:24] : bram_doutb[31:24];

  wire        bram_wea   = ram_sel && ((mem_wstrb == 4'b1111) || rmw_state);
  wire        bram_ena   = bram_wea;
  wire [11:0] bram_addra = mem_addr[13:2];
  wire [31:0] bram_dina  = rmw_state ? rmw_merged_data : mem_wdata;

  bram_ecc #(
      .WORDS     (MEM_SIZE),
      .ADDR_WIDTH(12),
      .INIT_FILE (FIRMWARE_FILE)
  ) ram (
      .clka         (clk),
      .ena          (bram_ena),
      .wea          (bram_wea),
      .addra        (bram_addra),
      .dina         (bram_dina),
      .injectsbiterr(1'b0),
      .injectdbiterr(1'b0),

      .clkb     (clk),
      .enb      (bram_enb),
      .addrb    (bram_addrb),
      .doutb    (bram_doutb),
      .sbiterr  (bram_sbiterr),
      .dbiterr  (bram_dbiterr),
      .rdaddrecc(bram_rdaddrecc)
  );
`else
  // 16 KB BRAM estándar sin ECC
  reg [31:0] memory[0:MEM_SIZE-1];
  initial $readmemh(FIRMWARE_FILE, memory);
`endif

  // Register used to hold the read data from memory or MMIO devices
  reg  [31:0] m_read_data;
  reg         m_read_en;

  // SimpleUART at 0x2000_0004 (div) and 0x2000_0008 (data)
  wire        uart_div_sel = mem_valid && (mem_addr == 32'h2000_0004);
  wire [31:0] uart_div_do;

  wire        uart_dat_sel = mem_valid && (mem_addr == 32'h2000_0008);
  wire [31:0] uart_dat_do;
  wire        uart_dat_wait;

  simpleuart uart (
      .clk         (clk),
      .resetn      (sys_resetn),
      .ser_tx      (ser_tx),
      .ser_rx      (ser_rx),
      .reg_div_we  (uart_div_sel ? mem_wstrb : 4'b0000),
      .reg_div_di  (mem_wdata),
      .reg_div_do  (uart_div_do),
      .reg_dat_we  (uart_dat_sel ? mem_wstrb[0] : 1'b0),
      // Qualified with !mem_ready so reg_dat_re pulses for only 1 cycle (cycle 1).
      // Since bus reads take 2 cycles (registered mem_ready), a 2-cycle pulse would
      // trigger a spurious clear-on-read on simpleuart and discard incoming RX bytes.
      .reg_dat_re  (uart_dat_sel && !mem_wstrb && !mem_ready),
      .reg_dat_di  (mem_wdata),
      .reg_dat_do  (uart_dat_do),
      .reg_dat_wait(uart_dat_wait)
  );

  // Memory and MMIO Controller
  always @(posedge clk) begin
    if (!sys_resetn) begin
      mem_ready <= 0;
      m_read_en <= 0;
      leds      <= 0;
      mem_rdata <= 0;
`ifdef PICORV32_ECC
      rmw_state <= 0;
`endif
    end else begin
      m_read_en <= 0;
      mem_ready <= mem_valid && !mem_ready && m_read_en;

`ifdef PICORV32_ECC
      if (m_read_en) begin
        mem_rdata <= bram_doutb;
      end
`else
      m_read_data <= memory[mem_addr[15:2]];
      mem_rdata   <= m_read_data;
`endif

      if (mem_valid && !mem_ready) begin
        // 1. RAM Access (16 KB)
        if ((mem_addr >> 2) < MEM_SIZE) begin
`ifdef PICORV32_ECC
          if (!mem_wstrb) begin
            m_read_en <= 1;
          end else if (mem_wstrb == 4'b1111) begin
            mem_ready <= 1;
          end else begin
            if (!rmw_state) begin
              rmw_state <= 1;
            end else begin
              mem_ready <= 1;
              rmw_state <= 0;
            end
          end
`else
          if (!mem_wstrb) begin
            m_read_en <= 1;
          end else begin
            if (mem_wstrb[0]) memory[mem_addr[15:2]][7:0] <= mem_wdata[7:0];
            if (mem_wstrb[1]) memory[mem_addr[15:2]][15:8] <= mem_wdata[15:8];
            if (mem_wstrb[2]) memory[mem_addr[15:2]][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) memory[mem_addr[15:2]][31:24] <= mem_wdata[31:24];
            mem_ready <= 1;
          end
`endif
        end  // 2. LEDs Register (0x1000_0000)
        else if (mem_addr == 32'h1000_0000) begin
          if (|mem_wstrb) leds <= mem_wdata[14:0];
          mem_rdata <= {17'b0, leds};
          mem_ready <= 1;
        end  // 3. UART Baud Divider (0x2000_0004)
        else if (uart_div_sel) begin
          mem_rdata <= uart_div_do;
          mem_ready <= 1;
        end  // 4. UART Data TX/RX (0x2000_0008)
        else if (uart_dat_sel) begin
          if (!uart_dat_wait) begin
            mem_rdata <= uart_dat_do;
            mem_ready <= 1;
          end
        end
      end
    end
  end

endmodule
