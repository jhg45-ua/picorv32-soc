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
