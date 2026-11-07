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
    #1; // Allow combinational propagation

    // 3. Verify voter masking and fault detection
    if (uut.cpu.fsm_fault_detected && (uut.cpu.cpu_state != 8'h80)) begin
      $display("[TMR TEST] SUCCESS: Voter masked the fault! Core sees Voted=0x%02h (NOT trap)", uut.cpu.cpu_state);
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
      $display("[TMR TEST] SUCCESS: Self-healing feedback verified! Branch A recovered to 0x%02h", uut.cpu.cpu_state_a);
      $display("[TMR TEST] Telemetry cleared: fsm_fault_detected = 0");
    end else begin
      $display("[TMR TEST] FAILURE: Self-healing failed! Branch A did not recover: A=0x%02h, B=0x%02h",
               uut.cpu.cpu_state_a, uut.cpu.cpu_state_b);
    end

    $display("========================================================\n");
  end
`endif

`ifdef PICORV32_TMR_RD
  // -------------------------------------------------------------
  // TMR Destination Register (latched_rd) Fault Injection Test
  // Injects an SEU into latched_rd_a and verifies that the voter
  // masks the corrupt register index and heals the branch.
  // -------------------------------------------------------------
  initial begin
    repeat (70000) @(posedge clk);

    $display("========================================================");
    $display("[TMR RD TEST] Starting Destination Reg SEU Fault Injection");
    $display("========================================================");

    if (uut.cpu.rd_fault_detected) begin
      $display("[TMR RD TEST] ERROR: Discrepancy already present in latched_rd before injection!");
    end

    @(posedge clk);
    $display("[TMR RD TEST] [%0t ns] Injecting SEU: forcing latched_rd_a = 5'd31...", $time);
    $display("[TMR RD TEST] Pre-SEU  rd: A=%0d, B=%0d, C=%0d -> Voted=%0d",
             uut.cpu.latched_rd_a, uut.cpu.latched_rd_b, uut.cpu.latched_rd_c, uut.cpu.latched_rd);

    force uut.cpu.latched_rd_a = 5'd31;
    #1;

    if (uut.cpu.rd_fault_detected && (uut.cpu.latched_rd != 5'd31)) begin
      $display("[TMR RD TEST] SUCCESS: Voter masked rd fault! Core sees Voted=%0d (NOT 31)", uut.cpu.latched_rd);
      $display("[TMR RD TEST] SUCCESS: Telemetry flag asserted (rd_fault_detected = 1)");
      $display("[TMR RD TEST] Mid-SEU  rd: A=%0d, B=%0d, C=%0d -> Voted=%0d",
               uut.cpu.latched_rd_a, uut.cpu.latched_rd_b, uut.cpu.latched_rd_c, uut.cpu.latched_rd);
    end else begin
      $display("[TMR RD TEST] FAILURE: RD voter did not mask fault or flag was not set!");
    end

    @(posedge clk);
    release uut.cpu.latched_rd_a;
    @(posedge clk);
    #1;

    if (!uut.cpu.rd_fault_detected && (uut.cpu.latched_rd_a == uut.cpu.latched_rd_b)) begin
      $display("[TMR RD TEST] SUCCESS: Self-healing verified! Branch A rd recovered to %0d", uut.cpu.latched_rd_a);
      $display("[TMR RD TEST] Telemetry cleared: rd_fault_detected = 0");
    end else begin
      $display("[TMR RD TEST] FAILURE: Self-healing failed! Branch A rd did not recover: A=%0d, B=%0d",
               uut.cpu.latched_rd_a, uut.cpu.latched_rd_b);
    end

    $display("========================================================\n");
  end
`endif

`ifdef PICORV32_TMR_MEM
  // -------------------------------------------------------------
  // TMR Memory FSM (mem_state) Fault Injection Test
  // Injects an SEU into mem_state_a and verifies that the voter
  // masks the corrupt state and heals the branch.
  // -------------------------------------------------------------
  initial begin
    repeat (80000) @(posedge clk);

    $display("========================================================");
    $display("[TMR MEM TEST] Starting Memory FSM SEU Fault Injection");
    $display("========================================================");

    if (uut.cpu.mem_fault_detected) begin
      $display("[TMR MEM TEST] ERROR: Discrepancy already present in mem_state before injection!");
    end

    @(posedge clk);
    $display("[TMR MEM TEST] [%0t ns] Injecting SEU: forcing mem_state_a = 2'b11...", $time);
    $display("[TMR MEM TEST] Pre-SEU  mem_state: A=%b, B=%b, C=%b -> Voted=%b",
             uut.cpu.mem_state_a, uut.cpu.mem_state_b, uut.cpu.mem_state_c, uut.cpu.mem_state);

    force uut.cpu.mem_state_a = 2'b11;
    #1;

    if (uut.cpu.mem_fault_detected && (uut.cpu.mem_state != 2'b11)) begin
      $display("[TMR MEM TEST] SUCCESS: Voter masked mem_state fault! Core sees Voted=%b", uut.cpu.mem_state);
      $display("[TMR MEM TEST] SUCCESS: Telemetry flag asserted (mem_fault_detected = 1)");
      $display("[TMR MEM TEST] Mid-SEU  mem_state: A=%b, B=%b, C=%b -> Voted=%b",
               uut.cpu.mem_state_a, uut.cpu.mem_state_b, uut.cpu.mem_state_c, uut.cpu.mem_state);
    end else begin
      $display("[TMR MEM TEST] FAILURE: MEM voter did not mask fault or flag was not set!");
    end

    @(posedge clk);
    release uut.cpu.mem_state_a;
    @(posedge clk);
    #1;

    if (!uut.cpu.mem_fault_detected && (uut.cpu.mem_state_a == uut.cpu.mem_state_b)) begin
      $display("[TMR MEM TEST] SUCCESS: Self-healing verified! Branch A mem_state recovered to %b", uut.cpu.mem_state_a);
      $display("[TMR MEM TEST] Telemetry cleared: mem_fault_detected = 0");
    end else begin
      $display("[TMR MEM TEST] FAILURE: Self-healing failed! Branch A mem_state did not recover: A=%b, B=%b",
               uut.cpu.mem_state_a, uut.cpu.mem_state_b);
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
      $display("[TMR PC TEST] SUCCESS: Voter masked PC fault! Core sees Voted=0x%08h", uut.cpu.reg_pc);
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
      $display("[TMR PC TEST] SUCCESS: Self-healing verified! Branch A PC recovered to 0x%08h", uut.cpu.reg_pc_a);
      $display("[TMR PC TEST] Telemetry cleared: pc_fault_detected = 0");
    end else begin
      $display("[TMR PC TEST] FAILURE: Self-healing failed! Branch A PC did not recover: A=0x%08h, B=0x%08h",
               uut.cpu.reg_pc_a, uut.cpu.reg_pc_b);
    end

    $display("========================================================\n");
  end
`endif

  // Simulation timeout and trap check
  initial begin
    repeat (1000000) @(posedge clk);
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
