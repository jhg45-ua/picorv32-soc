`timescale 1ns / 1ps

module ecc_secded32_dec (
    input  wire [38:0] code_in,
    output wire [31:0] data_out,
    output wire [ 6:0] syndrome,
    output wire        sbiterr,
    output wire        dbiterr
);
  wire [31:0] data_raw = code_in[31:0];
  wire [ 6:0] ecc_raw = code_in[38:32];
  wire [ 6:0] ecc_calc;

  ecc_secded32_enc enc (
      .data_in (data_raw),
      .ecc_out (ecc_calc),
      .code_out()           // Leave code_out unconnected because we don't need it here
  );

  // Syndrome calculation: XOR of received ECC and calculated ECC, assign sbiterr when syndrome is non-zero, assign dbiterr when syndrome is non-zero and sbiterr is zero
  assign syndrome = ecc_raw ^ ecc_calc;
  assign sbiterr  = ^syndrome;
  assign dbiterr  = (syndrome != 7'b0) & ~sbiterr;

  // Correction mask generation for the 32 data bits
  wire [31:0] err_mask;

  assign err_mask[0] = (syndrome == 7'h0b);
  assign err_mask[1] = (syndrome == 7'h13);
  assign err_mask[2] = (syndrome == 7'h23);
  assign err_mask[3] = (syndrome == 7'h43);
  assign err_mask[4] = (syndrome == 7'h0d);
  assign err_mask[5] = (syndrome == 7'h15);
  assign err_mask[6] = (syndrome == 7'h25);
  assign err_mask[7] = (syndrome == 7'h45);
  assign err_mask[8] = (syndrome == 7'h29);
  assign err_mask[9] = (syndrome == 7'h49);
  assign err_mask[10] = (syndrome == 7'h31);
  assign err_mask[11] = (syndrome == 7'h51);
  assign err_mask[12] = (syndrome == 7'h61);
  assign err_mask[13] = (syndrome == 7'h0e);
  assign err_mask[14] = (syndrome == 7'h16);
  assign err_mask[15] = (syndrome == 7'h26);
  assign err_mask[16] = (syndrome == 7'h46);
  assign err_mask[17] = (syndrome == 7'h1a);
  assign err_mask[18] = (syndrome == 7'h2a);
  assign err_mask[19] = (syndrome == 7'h4a);
  assign err_mask[20] = (syndrome == 7'h32);
  assign err_mask[21] = (syndrome == 7'h52);
  assign err_mask[22] = (syndrome == 7'h1c);
  assign err_mask[23] = (syndrome == 7'h2c);
  assign err_mask[24] = (syndrome == 7'h4c);
  assign err_mask[25] = (syndrome == 7'h34);
  assign err_mask[26] = (syndrome == 7'h54);
  assign err_mask[27] = (syndrome == 7'h64);
  assign err_mask[28] = (syndrome == 7'h38);
  assign err_mask[29] = (syndrome == 7'h58);
  assign err_mask[30] = (syndrome == 7'h68);
  assign err_mask[31] = (syndrome == 7'h70);

  assign data_out = data_raw ^ err_mask;
endmodule
