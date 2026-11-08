`timescale 1 ns / 1 ps

module system_tb;
  reg clk = 1;
  always #5 clk = ~clk;  // 100 MHz clock

  reg resetn = 0;
  initial begin
    if ($test$plusargs("vcd")) begin
      $dumpfile("system.vcd");
      $dumpvars(0, system_tb);
    end
    repeat (10) @(posedge clk);
    resetn <= 1;
  end

  wire trap;
  wire [14:0] leds;
  wire ser_tx;
  reg ser_rx = 1'b1;

  system uut (
      .clk   (clk),
      .resetn(resetn),
      .trap  (trap),
      .leds  (leds),
      .ser_tx(ser_tx),
      .ser_rx(ser_rx)
  );

  // -------------------------------------------------------------
  // UART RX Decoder (Captures ser_tx and prints characters)
  // -------------------------------------------------------------
  localparam integer BIT_CYCLES = 868;  // 100 MHz / 115200
  localparam integer HALF_BIT = 434;
  reg [7:0] uart_buf;
  always begin
    @(negedge ser_tx);  // Start bit edge
    repeat (HALF_BIT) @(posedge clk);  // Align to middle of start bit
    // Sample 8 data bits (LSB first)
    repeat (8) begin
      repeat (BIT_CYCLES) @(posedge clk);
      uart_buf = {ser_tx, uart_buf[7:1]};
    end
    // Wait for stop bit
    repeat (BIT_CYCLES) @(posedge clk);
    $write("%c", uart_buf);
    $fflush;
  end
  // Monitor LED changes
  always @(leds) begin
    $display("[%0t ns] LEDs updated: 15'b%b (0x%04h)", $time, leds, leds);
  end

`ifdef PICORV32_TMR_FSM
  // -------------------------------------------------------------
  // TMR Fault Injection Test
  // Injects a Single Event Upset (SEU) into cpu_state_a and verifies
  // that the voter masks the fault and heals the branch.
  // -------------------------------------------------------------
  initial begin
    // Wait for boot sequence and RAM test to start
    repeat (50000) @(posedge clk);

    $display("\n========================================================");
    $display("[TMR TEST] Starting SEU Fault Injection Verification");
    $display("========================================================");

    // 1. Check initial healthy status
    if (uut.cpu.fsm_fault_detected) begin
      $display("[TMR TEST] ERROR: Discrepancy already present before injection!");
    end

    // 2. Inject bit-flip into Branch A (force to cpu_state_trap: 8'h80)
    @(posedge clk);
    $display("[TMR TEST] [%0t ns] Injecting SEU: forcing cpu_state_a = 0x80 (TRAP)...", $time);
    $display("[TMR TEST] Pre-SEU  State: A=0x%02h, B=0x%02h, C=0x%02h -> Voted=0x%02h",
             uut.cpu.cpu_state_a, uut.cpu.cpu_state_b, uut.cpu.cpu_state_c, uut.cpu.cpu_state);

    force uut.cpu.cpu_state_a = 8'h80;
    #1;  // Allow combinational propagation

    // 3. Verify voter masking and fault detection
    if (uut.cpu.fsm_fault_detected && (uut.cpu.cpu_state != 8'h80)) begin
      $display("[TMR TEST] SUCCESS: Voter masked the fault! Core sees Voted=0x%02h (NOT trap)",
               uut.cpu.cpu_state);
      $display("[TMR TEST] SUCCESS: Telemetry flag asserted (fsm_fault_detected = 1)");
      $display("[TMR TEST] Mid-SEU  State: A=0x%02h, B=0x%02h, C=0x%02h -> Voted=0x%02h",
               uut.cpu.cpu_state_a, uut.cpu.cpu_state_b, uut.cpu.cpu_state_c, uut.cpu.cpu_state);
    end else begin
      $display("[TMR TEST] FAILURE: Voter did not mask fault or flag was not set!");
    end

    // 4. Release force and verify self-healing feedback on next clock edges
    @(posedge clk);
    release uut.cpu.cpu_state_a;
    @(posedge clk);
    #1;

    if (!uut.cpu.fsm_fault_detected && (uut.cpu.cpu_state_a == uut.cpu.cpu_state_b)) begin
      $display("[TMR TEST] SUCCESS: Self-healing feedback verified! Branch A recovered to 0x%02h",
               uut.cpu.cpu_state_a);
      $display("[TMR TEST] Telemetry cleared: fsm_fault_detected = 0");
    end else begin
      $display(
          "[TMR TEST] FAILURE: Self-healing failed! Branch A did not recover: A=0x%02h, B=0x%02h",
          uut.cpu.cpu_state_a, uut.cpu.cpu_state_b);
    end

    $display("========================================================\n");
  end
`endif

`ifdef PICORV32_TMR_CTRL
  // -------------------------------------------------------------
  // TMR CTRL Fault Injection Test (latched_rd)
  // Injects an SEU into latched_rd_a and verifies that the voter
  // masks the corrupted register address and heals the branch.
  // -------------------------------------------------------------
  initial begin
    repeat (70000) @(posedge clk);

    $display("========================================================");
    $display("[TMR CTRL TEST] Starting latched_rd SEU Fault Injection Verification");
    $display("========================================================");

    if (uut.cpu.latched_rd_fault_detected) begin
      $display("[TMR CTRL TEST] ERROR: Discrepancy present before injection!");
    end

    @(posedge clk);
    $display("[TMR CTRL TEST] [%0t ns] Injecting SEU: forcing latched_rd_a = 5'd31...", $time);
    $display("[TMR CTRL TEST] Pre-SEU  RD: A=%0d, B=%0d, C=%0d -> Voted=%0d", uut.cpu.latched_rd_a,
             uut.cpu.latched_rd_b, uut.cpu.latched_rd_c, uut.cpu.latched_rd);

    force uut.cpu.latched_rd_a = 5'd31;
    #1;

    if (uut.cpu.latched_rd_fault_detected && (uut.cpu.latched_rd != 5'd31)) begin
      $display("[TMR CTRL TEST] SUCCESS: Voter masked RD fault! Core sees Voted=%0d",
               uut.cpu.latched_rd);
      $display("[TMR CTRL TEST] SUCCESS: Telemetry flag asserted (latched_rd_fault_detected = 1)");
      $display("[TMR CTRL TEST] Mid-SEU  RD: A=%0d, B=%0d, C=%0d -> Voted=%0d",
               uut.cpu.latched_rd_a, uut.cpu.latched_rd_b, uut.cpu.latched_rd_c,
               uut.cpu.latched_rd);
    end else begin
      $display("[TMR CTRL TEST] FAILURE: Voter did not mask fault or flag was not set!");
    end

    @(posedge clk);
    release uut.cpu.latched_rd_a;
    @(posedge clk);
    #1;

    if (!uut.cpu.latched_rd_fault_detected && (uut.cpu.latched_rd_a == uut.cpu.latched_rd_b)) begin
      $display("[TMR CTRL TEST] SUCCESS: Self-healing verified! Branch A RD recovered to %0d",
               uut.cpu.latched_rd_a);
      $display("[TMR CTRL TEST] Telemetry cleared: latched_rd_fault_detected = 0");
    end else begin
      $display("[TMR CTRL TEST] FAILURE: Self-healing failed! A=%0d, B=%0d", uut.cpu.latched_rd_a,
               uut.cpu.latched_rd_b);
    end

    $display("========================================================\n");
  end
`endif

`ifdef PICORV32_TMR_MEM
  // -------------------------------------------------------------
  // TMR MEM Fault Injection Test (mem_state)
  // Injects an SEU into mem_state_a and verifies that the voter
  // masks the corrupted bus state and heals the branch.
  // -------------------------------------------------------------
  initial begin
    repeat (80000) @(posedge clk);

    $display("========================================================");
    $display("[TMR MEM TEST] Starting mem_state SEU Fault Injection Verification");
    $display("========================================================");

    if (uut.cpu.mem_state_fault_detected) begin
      $display("[TMR MEM TEST] ERROR: Discrepancy present before injection!");
    end

    @(posedge clk);
    $display("[TMR MEM TEST] [%0t ns] Injecting SEU: forcing mem_state_a = 2'b11...", $time);
    $display("[TMR MEM TEST] Pre-SEU  MEM_STATE: A=%0d, B=%0d, C=%0d -> Voted=%0d",
             uut.cpu.mem_state_a, uut.cpu.mem_state_b, uut.cpu.mem_state_c, uut.cpu.mem_state);

    force uut.cpu.mem_state_a = 2'b11;
    #1;

    if (uut.cpu.mem_state_fault_detected && (uut.cpu.mem_state != 2'b11)) begin
      $display("[TMR MEM TEST] SUCCESS: Voter masked mem_state fault! Core sees Voted=%0d",
               uut.cpu.mem_state);
      $display("[TMR MEM TEST] SUCCESS: Telemetry flag asserted (mem_state_fault_detected = 1)");
      $display("[TMR MEM TEST] Mid-SEU  MEM_STATE: A=%0d, B=%0d, C=%0d -> Voted=%0d",
               uut.cpu.mem_state_a, uut.cpu.mem_state_b, uut.cpu.mem_state_c, uut.cpu.mem_state);
    end else begin
      $display("[TMR MEM TEST] FAILURE: Voter did not mask fault or flag was not set!");
    end

    @(posedge clk);
    release uut.cpu.mem_state_a;
    @(posedge clk);
    #1;

    if (!uut.cpu.mem_state_fault_detected && (uut.cpu.mem_state_a == uut.cpu.mem_state_b)) begin
      $display("[TMR MEM TEST] SUCCESS: Self-healing verified! Branch A mem_state recovered to %0d",
               uut.cpu.mem_state_a);
      $display("[TMR MEM TEST] Telemetry cleared: mem_state_fault_detected = 0");
    end else begin
      $display("[TMR MEM TEST] FAILURE: Self-healing failed! A=%0d, B=%0d", uut.cpu.mem_state_a,
               uut.cpu.mem_state_b);
    end

    $display("========================================================\n");
  end
`endif

`ifdef PICORV32_TMR_PC
  // -------------------------------------------------------------
  // TMR PC Fault Injection Test
  // Injects an SEU into reg_pc_a and verifies that the voter masks
  // the corrupted address and heals the branch.
  // -------------------------------------------------------------
  initial begin
    // Wait for the FSM test to finish, then test PC hardening
    repeat (60000) @(posedge clk);

    $display("========================================================");
    $display("[TMR PC TEST] Starting PC SEU Fault Injection Verification");
    $display("========================================================");

    // 1. Check initial healthy status
    if (uut.cpu.pc_fault_detected) begin
      $display("[TMR PC TEST] ERROR: Discrepancy already present in PC before injection!");
    end

    // 2. Inject SEU into reg_pc_a (corrupt to an invalid address)
    @(posedge clk);
    $display("[TMR PC TEST] [%0t ns] Injecting SEU: forcing reg_pc_a = 0xDEAD0000...", $time);
    $display("[TMR PC TEST] Pre-SEU  PC: A=0x%08h, B=0x%08h, C=0x%08h -> Voted=0x%08h",
             uut.cpu.reg_pc_a, uut.cpu.reg_pc_b, uut.cpu.reg_pc_c, uut.cpu.reg_pc);

    force uut.cpu.reg_pc_a = 32'hdead0000;
    #1;

    // 3. Verify voter masking and fault detection
    if (uut.cpu.pc_fault_detected && (uut.cpu.reg_pc != 32'hdead0000)) begin
      $display("[TMR PC TEST] SUCCESS: Voter masked PC fault! Core sees Voted=0x%08h",
               uut.cpu.reg_pc);
      $display("[TMR PC TEST] SUCCESS: Telemetry flag asserted (pc_fault_detected = 1)");
      $display("[TMR PC TEST] Mid-SEU  PC: A=0x%08h, B=0x%08h, C=0x%08h -> Voted=0x%08h",
               uut.cpu.reg_pc_a, uut.cpu.reg_pc_b, uut.cpu.reg_pc_c, uut.cpu.reg_pc);
    end else begin
      $display("[TMR PC TEST] FAILURE: PC voter did not mask fault or flag was not set!");
    end

    // 4. Release force and verify self-healing feedback on next clock cycle
    @(posedge clk);
    release uut.cpu.reg_pc_a;
    @(posedge clk);
    #1;

    if (!uut.cpu.pc_fault_detected && (uut.cpu.reg_pc_a == uut.cpu.reg_pc_b)) begin
      $display("[TMR PC TEST] SUCCESS: Self-healing verified! Branch A PC recovered to 0x%08h",
               uut.cpu.reg_pc_a);
      $display("[TMR PC TEST] Telemetry cleared: pc_fault_detected = 0");
    end else begin
      $display(
          "[TMR PC TEST] FAILURE: Self-healing failed! Branch A PC did not recover: A=0x%08h, B=0x%08h",
          uut.cpu.reg_pc_a, uut.cpu.reg_pc_b);
    end

    $display("========================================================\n");
  end
`endif

`ifdef PICORV32_ECC
  // =============================================================
  // Test 1: SEU on Register File (Auto-Scrubbing Verification)
  // =============================================================
  initial begin
    // Wait for the system to reach steady state
    repeat (95000) @(posedge clk);

    $display("\n========================================================");
    $display("[ECC REGS TEST] Starting Register File SEU & Auto-Scrubbing Test");
    $display("========================================================");

    // Check initial healthy status
    #1;
    if (uut.cpu.regfile_sbiterr || uut.cpu.regfile_dbiterr) begin
      $display("[ECC REGS TEST] ERROR: Register file already reports errors before test!");
    end

    // Inject a single-bit error (SEU) into active register x15 (a5, inverted index ~5'd15 = 16)
    @(posedge clk);
    $display("[ECC REGS TEST] [%0t ns] Injecting SEU into register x15 (a5, idx 16)...", $time);
    $display("[ECC REGS TEST] Pre-SEU  word[16]: 0x%010h", uut.cpu.cpuregs.regs[16]);

    uut.cpu.cpuregs.regs[16] = uut.cpu.cpuregs.regs[16] ^ 39'h1;
    $display("[ECC REGS TEST] Post-SEU word[16]: 0x%010h (corrupted)", uut.cpu.cpuregs.regs[16]);

    // Wait synchronously on clock edges for the CPU to read x15 and trigger the sbiterr flag
    while (!uut.cpu.regfile_sbiterr) begin
      @(posedge clk);
      #1;
    end
    $display(
        "[ECC REGS TEST] [%0t ns] SUCCESS: Single-bit error detected on read! regfile_sbiterr = 1",
        $time);

    // Wait for the next clock edge to allow auto-scrubbing to write back the corrected value
    @(posedge clk);
    #1;  // Wait combinational propagation after the clock edge
    if (!uut.cpu.regfile_sbiterr && (uut.cpu.cpuregs.regs[16][0] == 1'b0)) begin
      $display("[ECC REGS TEST] SUCCESS: Auto-scrubbing verified! Register healed: 0x%010h",
               uut.cpu.cpuregs.regs[16]);
      $display("[ECC REGS TEST] Telemetry cleared: regfile_sbiterr = 0");
    end else begin
      $display("[ECC REGS TEST] FAILURE: Auto-scrubbing failed! word[16] = 0x%010h, sbiterr = %b",
               uut.cpu.cpuregs.regs[16], uut.cpu.regfile_sbiterr);
    end

    $display("========================================================\n");
  end

  // =============================================================
  // Test 2: MEU on Register File (Double-Bit Error Detection)
  // =============================================================
  // Save the original value of register x15 (idx 16) before injecting errors
  reg [38:0] orig_reg16;

  initial begin
    // Wait for Test 1 to finish and system to remain stable
    repeat (110000) @(posedge clk);

    $display("========================================================");
    $display("[ECC REGS TEST 2] Starting Register File Double-Bit Error (MEU) Test");
    $display("========================================================");

    // Check initial healthy status
    #1;
    if (uut.cpu.regfile_sbiterr || uut.cpu.regfile_dbiterr) begin
      $display("[ECC REGS TEST 2] ERROR: Register file already reports errors before MEU test!");
    end

    // Save clean value and inject 2 simultaneous bit-flips (bits 0 and 1) into x15 (idx 16)
    @(posedge clk);
    orig_reg16 = uut.cpu.cpuregs.regs[16];
    $display("[ECC REGS TEST 2] [%0t ns] Injecting MEU into register x15 (a5, idx 16)...", $time);
    $display("[ECC REGS TEST 2] Healthy word[16]: 0x%010h", orig_reg16);

    uut.cpu.cpuregs.regs[16] = orig_reg16 ^ 39'h3;  // Flip bit 0 and bit 1
    $display("[ECC REGS TEST 2] Corrupted word[16]: 0x%010h (2 bit-flips)",
             uut.cpu.cpuregs.regs[16]);

    // Synchronous sampling waiting for double-bit error detection
    while (!uut.cpu.regfile_dbiterr) begin
      @(posedge clk);
      #1;
    end

    // Verify uncorrectable error flags
    if (uut.cpu.regfile_dbiterr && !uut.cpu.regfile_sbiterr) begin
      $display(
          "[ECC REGS TEST 2] SUCCESS: Uncorrectable double error correctly detected! (dbiterr=1, sbiterr=0)");
    end else begin
      $display("[ECC REGS TEST 2] FAILURE: Error flags incorrect! (dbiterr=%b, sbiterr=%b)",
               uut.cpu.regfile_dbiterr, uut.cpu.regfile_sbiterr);
    end

    // Verify auto-scrubbing is inhibited (must NOT overwrite on double error)
    @(posedge clk);
    #1;
    if (uut.cpu.cpuregs.regs[16] == (orig_reg16 ^ 39'h3)) begin
      $display(
          "[ECC REGS TEST 2] SUCCESS: Memory preserved! Auto-scrubbing correctly inhibited on MEU.");
    end else begin
      $display(
          "[ECC REGS TEST 2] FAILURE: Memory was illegally modified during MEU! word[16]=0x%010h",
          uut.cpu.cpuregs.regs[16]);
    end

    // Restore healthy register value so firmware continues execution towards BRAM tests
    @(posedge clk);
    uut.cpu.cpuregs.regs[16] = orig_reg16;
    @(posedge clk);
    #1;
    if (!uut.cpu.regfile_dbiterr && !uut.cpu.regfile_sbiterr) begin
      $display(
          "[ECC REGS TEST 2] SUCCESS: Register restored and telemetry cleared (dbiterr=0, sbiterr=0)");
    end

    $display("========================================================\n");
  end

  // =============================================================
  // Test 3: SEU on 16 KB BRAM (Instruction Fetch & Correction)
  // =============================================================
  reg [38:0] orig_bram_word;
  localparam [11:0] TEST3_ADDR = 12'd8;  // PC 0x20: lbu a4, 0(a0) in puts()

  initial begin
    // Wait for Test 2 to finish and system to remain stable
    repeat (125000) @(posedge clk);

    $display("========================================================");
    $display("[ECC BRAM TEST 3] Starting 16 KB BRAM Single-Bit Error (SEU) Test");
    $display("========================================================");

    // Check initial healthy status
    #1;
    if (uut.bram_sbiterr || uut.bram_dbiterr) begin
      $display("[ECC BRAM TEST 3] ERROR: BRAM already reports error before test!");
    end

    // Save clean word and inject 1 bit-flip into active instruction memory (word 129, PC 0x204)
    @(posedge clk);
    orig_bram_word = uut.ram.mem[TEST3_ADDR];
    $display("[ECC BRAM TEST 3] [%0t ns] Injecting SEU into BRAM word addr %0d (PC 0x%03h)...",
             $time, TEST3_ADDR, TEST3_ADDR << 2);
    $display("[ECC BRAM TEST 3] Healthy word: 0x%010h", orig_bram_word);

    uut.ram.mem[TEST3_ADDR] = orig_bram_word ^ 39'h1;  // Flip bit 0
    $display("[ECC BRAM TEST 3] Corrupted word: 0x%010h (1 bit-flip)", uut.ram.mem[TEST3_ADDR]);

    // Synchronous sampling waiting for SEU detection on read
    while (!uut.bram_sbiterr) begin
      @(posedge clk);
      #1;
    end

    // Verify detection flags and address telemetry
    if (uut.bram_sbiterr && !uut.bram_dbiterr && (uut.bram_rdaddrecc == TEST3_ADDR)) begin
      $display(
          "[ECC BRAM TEST 3] SUCCESS: Single-bit error detected on BRAM read! (sbiterr=1, dbiterr=0, addr=%0d)",
          uut.bram_rdaddrecc);
    end else begin
      $display(
          "[ECC BRAM TEST 3] FAILURE: Flags incorrect or address mismatch! (sbiterr=%b, dbiterr=%b, addr=%0d)",
          uut.bram_sbiterr, uut.bram_dbiterr, uut.bram_rdaddrecc);
    end

    // Verify processor execution continues without trap
    if (!uut.trap) begin
      $display(
          "[ECC BRAM TEST 3] SUCCESS: Instruction corrected on-the-fly! Core executed safely without trap.");
    end

    // Restore original clean word in BRAM
    @(posedge clk);
    uut.ram.mem[TEST3_ADDR] = orig_bram_word;
    @(posedge clk);
    #1;
    if (!uut.bram_sbiterr && !uut.bram_dbiterr) begin
      $display(
          "[ECC BRAM TEST 3] SUCCESS: BRAM word restored and telemetry cleared (sbiterr=0, dbiterr=0)");
    end

    $display("========================================================\n");
  end

  // =============================================================
  // Test 4: MEU on 16 KB BRAM (Double-Bit Error Detection)
  // =============================================================
  reg [38:0] orig_bram_word4;
  localparam [11:0] TEST4_ADDR = 12'd8;  // PC 0x20: lbu a4, 0(a0) in puts()

  initial begin
    // Wait for Test 3 to finish and system to remain stable
    repeat (140000) @(posedge clk);

    $display("========================================================");
    $display("[ECC BRAM TEST 4] Starting 16 KB BRAM Double-Bit Error (MEU) Test");
    $display("========================================================");

    // Check initial healthy status
    #1;
    if (uut.bram_sbiterr || uut.bram_dbiterr) begin
      $display("[ECC BRAM TEST 4] ERROR: BRAM already reports error before MEU test!");
    end

    // Save clean word and inject 2 bit-flips (bits 0 and 1) into instruction memory
    @(posedge clk);
    orig_bram_word4 = uut.ram.mem[TEST4_ADDR];
    $display("[ECC BRAM TEST 4] [%0t ns] Injecting MEU into BRAM word addr %0d (PC 0x%03h)...",
             $time, TEST4_ADDR, TEST4_ADDR << 2);
    $display("[ECC BRAM TEST 4] Healthy word: 0x%010h", orig_bram_word4);

    uut.ram.mem[TEST4_ADDR] = orig_bram_word4 ^ 39'h0300000000;  // Flip bit 0 and bit 1
    $display("[ECC BRAM TEST 4] Corrupted word: 0x%010h (2 bit-flips)", uut.ram.mem[TEST4_ADDR]);

    // 3. Synchronous sampling waiting for double-bit error detection
    while (!uut.bram_dbiterr) begin
      @(posedge clk);
      #1;
    end

    // Verify detection flags and address telemetry
    if (uut.bram_dbiterr && !uut.bram_sbiterr && (uut.bram_rdaddrecc == TEST4_ADDR)) begin
      $display(
          "[ECC BRAM TEST 4] SUCCESS: Uncorrectable double error correctly detected! (dbiterr=1, sbiterr=0, addr=%0d)",
          uut.bram_rdaddrecc);
    end else begin
      $display(
          "[ECC BRAM TEST 4] FAILURE: Flags incorrect or address mismatch! (dbiterr=%b, sbiterr=%b, addr=%0d)",
          uut.bram_dbiterr, uut.bram_sbiterr, uut.bram_rdaddrecc);
    end

    // Restore original clean word in BRAM to let CPU resume cleanly
    @(posedge clk);
    uut.ram.mem[TEST4_ADDR] = orig_bram_word4;
    @(posedge clk);
    #1;
    if (!uut.bram_sbiterr && !uut.bram_dbiterr) begin
      $display(
          "[ECC BRAM TEST 4] SUCCESS: BRAM word restored and telemetry cleared (sbiterr=0, dbiterr=0)");
    end

    $display("========================================================\n");
  end
`endif

  // Simulation timeout and trap check
  initial begin
    repeat (4000000) @(posedge clk);
    $display("\n[SIMULATION DONE] Timeout reached safely.");
    $finish;
  end
  always @(posedge clk) begin
    if (resetn && trap) begin
      $display("\n[SIMULATION ERROR] CPU triggered TRAP at %0t ns!", $time);
      $finish;
    end
  end
endmodule
