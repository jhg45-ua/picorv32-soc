`timescale 1 ns / 1 ps

module system #(
    parameter integer MEM_SIZE = 4096,
    parameter FIRMWARE_FILE = "firmware.hex"
) (
    input             clk,       // 100 MHz oscillator from Nexys A7 (E3)
    input             resetn,    // CPU_RESETN red push button (C12, active-low)
    output            trap,      // High if CPU executes illegal insn -> LED[15]
    output reg [14:0] leds,      // Lower 15 user LEDs -> LED[14:0]
    output            ser_tx,    // UART TX -> FTDI RX (D4)
    input             ser_rx     // UART RX <- FTDI TX (C4)
);

    // Power-on reset generator
    reg [5:0] reset_cnt = 0;
    wire sys_resetn = &reset_cnt;

    always @(posedge clk) begin
        if (!resetn)
            reset_cnt <= 0;
        else if (!sys_resetn)
            reset_cnt <= reset_cnt + 1;
    end

    // Memory bus wires
    wire        mem_valid;
    wire        mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
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
        .clk      (clk       ),
        .resetn   (sys_resetn),
        .trap     (trap      ),
        .mem_valid(mem_valid ),
        .mem_instr(mem_instr ),
        .mem_ready(mem_ready ),
        .mem_addr (mem_addr  ),
        .mem_wdata(mem_wdata ),
        .mem_wstrb(mem_wstrb ),
        .mem_rdata(mem_rdata ),
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

    // 16 KB BRAM memory
    reg [31:0] memory [0:MEM_SIZE-1];
    initial $readmemh(FIRMWARE_FILE, memory);

    // Register used to hold the read data from memory or MMIO devices
    reg [31:0] m_read_data;
    reg m_read_en;

    // SimpleUART at 0x2000_0004 (div) and 0x2000_0008 (data)
    wire        uart_div_sel = mem_valid && (mem_addr == 32'h2000_0004);
    wire [31:0] uart_div_do;

    wire        uart_dat_sel = mem_valid && (mem_addr == 32'h2000_0008);
    wire [31:0] uart_dat_do;
    wire        uart_dat_wait;

    simpleuart uart (
        .clk         (clk          ),
        .resetn      (sys_resetn   ),
        .ser_tx      (ser_tx       ),
        .ser_rx      (ser_rx       ),
        .reg_div_we  (uart_div_sel ? mem_wstrb : 4'b0000),
        .reg_div_di  (mem_wdata    ),
        .reg_div_do  (uart_div_do  ),
        .reg_dat_we  (uart_dat_sel ? mem_wstrb[0] : 1'b0),
        .reg_dat_re  (uart_dat_sel && !mem_wstrb),
        .reg_dat_di  (mem_wdata    ),
        .reg_dat_do  (uart_dat_do  ),
        .reg_dat_wait(uart_dat_wait)
    );

    // Memory and MMIO Controller
    always @(posedge clk) begin
        if (!sys_resetn) begin
            mem_ready   <= 0;
            m_read_en   <= 0;
            leds        <= 0;
            mem_rdata   <= 0;
        end else begin
            m_read_en <= 0;
            mem_ready <= mem_valid && !mem_ready && m_read_en;

            m_read_data <= memory[mem_addr[15:2]];
            mem_rdata   <= m_read_data;

            if (mem_valid && !mem_ready) begin
                // 1. RAM Access (16 KB)
                if ((mem_addr >> 2) < MEM_SIZE) begin
                    if (!mem_wstrb) begin
                        m_read_en <= 1;
                    end else begin
                        if (mem_wstrb[0]) memory[mem_addr[15:2]][ 7: 0] <= mem_wdata[ 7: 0];
                        if (mem_wstrb[1]) memory[mem_addr[15:2]][15: 8] <= mem_wdata[15: 8];
                        if (mem_wstrb[2]) memory[mem_addr[15:2]][23:16] <= mem_wdata[23:16];
                        if (mem_wstrb[3]) memory[mem_addr[15:2]][31:24] <= mem_wdata[31:24];
                        mem_ready <= 1;
                    end
                end
                // 2. LEDs Register (0x1000_0000)
                else if (mem_addr == 32'h1000_0000) begin
                    if (|mem_wstrb)
                        leds <= mem_wdata[14:0];
                    mem_rdata <= {17'b0, leds};
                    mem_ready <= 1;
                end
                // 3. UART Baud Divider (0x2000_0004)
                else if (uart_div_sel) begin
                    mem_rdata <= uart_div_do;
                    mem_ready <= 1;
                end
                // 4. UART Data TX/RX (0x2000_0008)
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
