`timescale 1ns / 1ps

module ecc_secded32_tb;

  reg     [31:0] tb_data_in;
  wire    [ 6:0] tb_ecc_clean;
  wire    [38:0] tb_code_clean;

  reg     [38:0] tb_code_corrupted;
  wire    [31:0] tb_data_out;
  wire    [ 6:0] tb_syndrome;
  wire           tb_sbiterr;
  wire           tb_dbiterr;

  integer        error_count = 0;
  integer i, j;

  ecc_secded32_enc enc (
      .data_in (tb_data_in),
      .ecc_out (tb_ecc_clean),
      .code_out(tb_code_clean)
  );

  ecc_secded32_dec dec (
      .code_in (tb_code_corrupted),
      .data_out(tb_data_out),
      .syndrome(tb_syndrome),
      .sbiterr (tb_sbiterr),
      .dbiterr (tb_dbiterr)
  );

  initial begin
    $display("==================================================");
    $display("Starting Unit Test: ecc_secded32 (SECDED)");
    $display("==================================================");

    // -------------------------------------------------------------------------
    // TEST 1: Error-free case (Clean word)
    // -------------------------------------------------------------------------
    tb_data_in = 32'hA5A5_5A5A;
    #1;
    tb_code_corrupted = tb_code_clean;  // Inject clean codeword untouched
    #1;

    if (tb_data_out!==tb_data_in||tb_sbiterr !== 1'b0||tb_dbiterr !== 1'b0||tb_syndrome!==7'b0) begin
      $display("[FAIL] Test 1: Clean word failed!");
      error_count = error_count + 1;
    end else begin
      $display("[PASS] Test 1: Clean word OK (syndrome=0, sbiterr=0, dbiterr=0)");
    end

    // -------------------------------------------------------------------------
    // TEST 2: Exhaustive 1-bit sweep (SEU) across all 39 bit positions
    // -------------------------------------------------------------------------
    $display("\n[TEST 2] Testing all 39 single-bit errors (SEU)...");
    for (i = 0; i < 39; i = i + 1) begin
      // Invert bit 'i'
      tb_code_corrupted = tb_code_clean ^ (39'd1 << i);
      #1;

      // Verify that sbiterr=1, dbiterr=0 and data was recovered 100%
      if (tb_sbiterr !== 1'b1 || tb_dbiterr !== 1'b0 || tb_data_out !== tb_data_in) begin
        $display(
            "[FAIL] SEU on bit %0d: sbiterr=%b, dbiterr=%b, data_out=0x%08h (expected=0x%08h)", i,
            tb_sbiterr, tb_dbiterr, tb_data_out, tb_data_in);
        error_count = error_count + 1;
      end
    end

    if (error_count == 0) begin
      $display("[PASS] All 39 single-bit errors successfully corrected!");
    end

    // -------------------------------------------------------------------------
    // TEST 3: Exhaustive 2-bit sweep (Double error / MBU) across all 741 pairs
    // -------------------------------------------------------------------------
    $display("\n[TEST 3] Testing all 741 double-bit error pairs (MBU)...");
    for (i = 0; i < 39; i = i + 1) begin
      for (j = i + 1; j < 39; j = j + 1) begin
        // Simultaneously invert bit 'i' and bit 'j'
        tb_code_corrupted = tb_code_clean ^ (39'd1 << i) ^ (39'd1 << j);
        #1;

        // Verify that sbiterr=0 and dbiterr=1 (detected as uncorrectable)
        if (tb_sbiterr !== 1'b0 || tb_dbiterr !== 1'b1) begin
          $display("[FAIL] MBU on bits (%0d, %0d): sbiterr=%b, dbiterr=%b, syndrome=0x%02h", i, j,
                   tb_sbiterr, tb_dbiterr, tb_syndrome);
          error_count = error_count + 1;
        end
      end
    end

    if (error_count == 0) begin
      $display("[PASS] All 741 double-bit errors successfully detected as uncorrectable!");
    end

    // -------------------------------------------------------------------------
    // Final Summary
    // -------------------------------------------------------------------------
    $display("\n==================================================");
    if (error_count == 0) begin
      $display(" >>> RESULT: ALL TESTS PASSED 100%% <<<");
    end else begin
      $display(" >>> RESULT: FAILED WITH %0d ERRORS <<<", error_count);
    end
    $display("==================================================");

    $finish;
  end
endmodule
