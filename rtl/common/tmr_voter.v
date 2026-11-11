`timescale 1ns / 1ps

module tmr_voter #(
    parameter integer WIDTH = 32
) (
    input wire [WIDTH-1:0] in_a,
    input wire [WIDTH-1:0] in_b,
    input wire [WIDTH-1:0] in_c,
    output wire [WIDTH-1:0] out,
    output wire fault_detected
);

  // Majority voting logic: If two or more inputs are the same, output that value
  assign out = (in_a & in_b) | (in_b & in_c) | (in_a & in_c);

  // Diff is the XOR of the input and the output. If any of the inputs differ from the output, it indicates a fault.
  wire [WIDTH-1:0] diff_a = in_a ^ out;
  wire [WIDTH-1:0] diff_b = in_b ^ out;
  wire [WIDTH-1:0] diff_c = in_c ^ out;

  // Fault detection: If any of the diffs are non-zero, a fault is detected
  assign fault_detected = |(diff_a | diff_b | diff_c);

endmodule
