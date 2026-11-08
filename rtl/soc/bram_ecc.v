`timescale 1ns / 1ps

module bram_ecc #(
    parameter integer WORDS = 4096,
    parameter integer ADDR_WIDTH = 12,
    parameter INIT_FILE = "build/firmware.hex"
) (
    input wire clka,
    input wire ena,
    input wire wea,
    input wire [ADDR_WIDTH-1:0] addra,
    input wire [31:0] dina,
    input wire injectsbiterr,
    input wire injectdbiterr,

    input wire clkb,
    input wire enb,
    input wire [ADDR_WIDTH-1:0] addrb,
    output wire [31:0] doutb,
    output wire sbiterr,
    output wire dbiterr,
    output wire [ADDR_WIDTH-1:0] rdaddrecc
);

`ifdef XILINX_ECC_IP
  blk_mem_gen_ecc xil_bram (
      .clka(clka),
      .ena(ena),
      .wea(wea),
      .addra(addra),
      .dina(dina),
      .injectsbiterr(injectsbiterr),
      .injectdbiterr(injectdbiterr),
      .clkb(clkb),
      .enb(enb),
      .addrb(addrb),
      .doutb(doutb),
      .sbiterr(sbiterr),
      .dbiterr(dbiterr),
      .rdaddrecc(rdaddrecc)
  );
`else
  reg [38:0] mem[0:WORDS-1];

  reg [38:0] raw_dout;
  reg [ADDR_WIDTH-1:0] reg_rdaddrecc;
  assign rdaddrecc = reg_rdaddrecc;

  // Port A: Write port with ECC encoding
  wire [38:0] enc_code;
  ecc_secded32_enc enc_inst (
      .data_in (dina),
      .code_out(enc_code),
      .ecc_out ()
  );

  wire [38:0] wr_data = injectdbiterr ? (enc_code ^ 39'h3) :
                        injectsbiterr ? (enc_code ^ 39'h1) :
                        enc_code;

  always @(posedge clka) begin
    if (ena && wea) begin
      mem[addra] <= wr_data;
    end
  end

  // Port B: Read port with ECC decoding
  always @(posedge clkb) begin
    if (enb) begin
      raw_dout      <= mem[addrb];
      reg_rdaddrecc <= addrb;
    end
  end

  ecc_secded32_dec dec_inst (
      .code_in (raw_dout),
      .data_out(doutb),
      .syndrome(),
      .sbiterr (sbiterr),
      .dbiterr (dbiterr)
  );

  // =============================================================
  // Firmware initialization for Simulation (Icarus / Verilator)
  // Loads firmware.hex (32b) and pre-calculates the 7 bits of ECC parity
  // =============================================================
  function [6:0] calc_ecc_parity(input [31:0] d);
    begin
      calc_ecc_parity[0] = d[0]  ^ d[1]  ^ d[2]  ^ d[3]  ^
                           d[4]  ^ d[5]  ^ d[6]  ^ d[7]  ^
                           d[8]  ^ d[9]  ^ d[10] ^ d[11] ^
                           d[12];

      calc_ecc_parity[1] = d[0]  ^ d[1]  ^ d[2]  ^ d[3]  ^
                           d[13] ^ d[14] ^ d[15] ^ d[16] ^
                           d[17] ^ d[18] ^ d[19] ^ d[20] ^
                           d[21];

      calc_ecc_parity[2] = d[4]  ^ d[5]  ^ d[6]  ^ d[7]  ^
                           d[13] ^ d[14] ^ d[15] ^ d[16] ^
                           d[22] ^ d[23] ^ d[24] ^ d[25] ^
                           d[26] ^ d[27];

      calc_ecc_parity[3] = d[0]  ^ d[4]  ^ d[8]  ^ d[9]  ^
                           d[13] ^ d[17] ^ d[18] ^ d[19] ^
                           d[22] ^ d[23] ^ d[24] ^ d[28] ^
                           d[29] ^ d[30];

      calc_ecc_parity[4] = d[1]  ^ d[5]  ^ d[10] ^ d[11] ^
                           d[14] ^ d[17] ^ d[20] ^ d[21] ^
                           d[22] ^ d[25] ^ d[26] ^ d[28] ^
                           d[29] ^ d[31];

      calc_ecc_parity[5] = d[2]  ^ d[6]  ^ d[8]  ^ d[10] ^
                           d[12] ^ d[15] ^ d[18] ^ d[20] ^
                           d[23] ^ d[25] ^ d[27] ^ d[28] ^
                           d[30] ^ d[31];

      calc_ecc_parity[6] = d[3]  ^ d[7]  ^ d[9]  ^ d[11] ^
                           d[12] ^ d[16] ^ d[19] ^ d[21] ^
                           d[24] ^ d[26] ^ d[27] ^ d[29] ^
                           d[30] ^ d[31];
    end
  endfunction

  reg [31:0] init_data[0:WORDS-1];
  integer i;

  initial begin
    for (i = 0; i < WORDS; i = i + 1) begin
      init_data[i] = 32'b0;
      mem[i]       = 39'b0;
    end

    $readmemh(INIT_FILE, init_data);

    for (i = 0; i < WORDS; i = i + 1) begin
      mem[i] = {calc_ecc_parity(init_data[i]), init_data[i]};
    end
  end
`endif

endmodule
