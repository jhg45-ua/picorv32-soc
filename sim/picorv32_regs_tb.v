`timescale 1ns / 1ps

module picorv32_regs_tb;

  reg clk = 0;
  always #5 clk = ~clk; // 100 MHz

  reg wen;
  reg [5:0] waddr;
  reg [5:0] raddr1;
  reg [5:0] raddr2;
  reg [31:0] wdata;
  wire [31:0] rdata1;
  wire [31:0] rdata2;
  wire sbiterr;
  wire dbiterr;

  picorv32_regs uut (
      .clk    (clk),
      .wen    (wen),
      .waddr  (waddr),
      .raddr1 (raddr1),
      .raddr2 (raddr2),
      .wdata  (wdata),
      .rdata1 (rdata1),
      .rdata2 (rdata2),
      .sbiterr(sbiterr),
      .dbiterr(dbiterr)
  );

  integer errors = 0;

  initial begin
    $display("==================================================");
    $display("Starting Unit Test: picorv32_regs ECC + Auto-Scrubbing");
    $display("==================================================");

    wen = 0;
    waddr = 0;
    raddr1 = 0;
    raddr2 = 0;
    wdata = 0;

    @(posedge clk);

    // -------------------------------------------------------------
    // Test 1: Write and clean read of register x1 and x2
    // -------------------------------------------------------------
    @(posedge clk);
    wen   <= 1;
    waddr <= 6'd1;
    wdata <= 32'hA5A5_1234;
    @(posedge clk);
    waddr <= 6'd2;
    wdata <= 32'h5A5A_BEEF;
    @(posedge clk);
    wen   <= 0;
    waddr <= 6'd0;
    wdata <= 32'h0;

    // Read back in 0 cycles (combinational)
    raddr1 = 6'd1;
    raddr2 = 6'd2;
    #1;

    if (rdata1 !== 32'hA5A5_1234 || rdata2 !== 32'h5A5A_BEEF || sbiterr !== 0 || dbiterr !== 0) begin
      $display("[FAIL] Test 1: Clean read mismatch! r1=0x%08h, r2=0x%08h, sbit=%b, dbit=%b",
               rdata1, rdata2, sbiterr, dbiterr);
      errors = errors + 1;
    end else begin
      $display("[PASS] Test 1: Clean register write and read OK");
    end

    // -------------------------------------------------------------
    // Test 2: SEU Injection in x1 + On-the-fly correction
    // Invert bit 10 of regs[~1] (register x1)
    // -------------------------------------------------------------
    @(posedge clk);
    $display("[TEST 2] Injecting 1-bit error (SEU) into x1...");
    uut.regs[~5'd1] = uut.regs[~5'd1] ^ 39'h0000000400; // Flip bit 10
    #1;

    // Verify combinational on-the-fly correction in 0 cycles
    if (rdata1 !== 32'hA5A5_1234) begin
      $display("[FAIL] Test 2: Data not corrected on the fly! Got 0x%08h", rdata1);
      errors = errors + 1;
    end else if (!sbiterr) begin
      $display("[FAIL] Test 2: sbiterr flag not asserted!");
      errors = errors + 1;
    end else begin
      $display("[PASS] Test 2: SEU corrected on-the-fly (rdata1=0x%08h, sbiterr=1)", rdata1);
    end

    // -------------------------------------------------------------
    // Test 3: Auto-Scrubbing (Self-Healing) verification
    // Allow 1 clock edge with wen == 0 to let auto-scrubbing write back
    // -------------------------------------------------------------
    @(posedge clk);
    #1;

    if (sbiterr !== 0) begin
      $display("[FAIL] Test 3: Auto-scrubbing failed! sbiterr still active = %b", sbiterr);
      errors = errors + 1;
    end else if (uut.regs[~5'd1][31:0] !== 32'hA5A5_1234) begin
      $display("[FAIL] Test 3: Stored word in memory not healed! regs[~1]=0x%08h", uut.regs[~5'd1][31:0]);
      errors = errors + 1;
    end else begin
      $display("[PASS] Test 3: Auto-scrubbing healed x1 successfully! (sbiterr returned to 0)");
    end

    // -------------------------------------------------------------
    // Test 4: Double-Bit Error (MBU) Detection
    // Invert bits 4 and 18 of regs[~2] (register x2)
    // -------------------------------------------------------------
    @(posedge clk);
    $display("[TEST 4] Injecting 2-bit error (MBU) into x2...");
    uut.regs[~5'd2] = uut.regs[~5'd2] ^ 39'h0000040010; // Flip bits 4 and 18
    #1;

    if (!dbiterr) begin
      $display("[FAIL] Test 4: dbiterr flag not asserted!");
      errors = errors + 1;
    end else if (sbiterr) begin
      $display("[FAIL] Test 4: sbiterr asserted on double-bit error!");
      errors = errors + 1;
    end else begin
      $display("[PASS] Test 4: MBU detected successfully as uncorrectable (dbiterr=1, sbiterr=0)");
    end

    // Verify auto-scrubbing did NOT overwrite register on double-bit error
    @(posedge clk);
    #1;
    if (!dbiterr) begin
      $display("[FAIL] Test 4: Memory was illegally modified during MBU!");
      errors = errors + 1;
    end else begin
      $display("[PASS] Test 4: Double error preserved without corrupting memory");
    end

    // -------------------------------------------------------------
    // Summary
    // -------------------------------------------------------------
    $display("==================================================");
    if (errors == 0) begin
      $display(" >>> RESULT: ALL TESTS PASSED 100%% <<<");
    end else begin
      $display(" >>> RESULT: %0d TESTS FAILED <<<", errors);
    end
    $display("==================================================");
    $finish;
  end

endmodule
