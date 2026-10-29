`timescale 1 ns / 1 ps

module system_tb;
    reg clk = 1;
    always #5 clk = ~clk; // 100 MHz clock

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
        .clk        (clk        ),
        .resetn     (resetn     ),
        .trap       (trap       ),
        .leds       (leds       ),
        .ser_tx     (ser_tx     ),
        .ser_rx     (ser_rx     )
    );

    // -------------------------------------------------------------
    // UART RX Decoder (Captures ser_tx and prints characters)
    // -------------------------------------------------------------
    localparam integer BIT_CYCLES = 868; // 100 MHz / 115200
    localparam integer HALF_BIT   = 434;
    reg [7:0] uart_buf;
    always begin
        @(negedge ser_tx); // Start bit edge
        repeat (HALF_BIT) @(posedge clk); // Align to middle of start bit
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
    // Simulation timeout and trap check
    initial begin
        repeat (5000000) @(posedge clk);
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
