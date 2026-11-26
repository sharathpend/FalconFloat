
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`timescale 1ns/1ps

// Self-checking testbench for karatsuba_mul and comba_mul against a * b, at 64x64
// (top level) and 53x53 (standalone units), with a few BASE / LIMB sizes.
// Run:  iverilog -g2012 mult_check_tb.sv karatsuba_mul.sv comba_mul.sv && vvp a.out
module mult_check_tb;
  parameter NUM_RANDOM = 50000;

  reg  [63:0]  a64, b64;
  wire [52:0]  a53 = a64[52:0], b53 = b64[52:0];
  wire [127:0] p_ka18, p_ka17, p_ka9, p_co16, p_co17, p_co12;
  wire [105:0] p53_ka18, p53_ka17, p53_co16, p53_co17;
  reg  [127:0] exp64;
  reg  [105:0] exp53;
  integer      n = 0, err = 0, i, j;

  karatsuba_mul #(.N(64), .BASE(18)) ka18   (.a(a64), .b(b64), .p(p_ka18));
  karatsuba_mul #(.N(64), .BASE(17)) ka17   (.a(a64), .b(b64), .p(p_ka17));
  karatsuba_mul #(.N(64), .BASE(9))  ka9    (.a(a64), .b(b64), .p(p_ka9));
  comba_mul     #(.N(64), .LIMB(16)) co16   (.a(a64), .b(b64), .p(p_co16));
  comba_mul     #(.N(64), .LIMB(17)) co17   (.a(a64), .b(b64), .p(p_co17));
  comba_mul     #(.N(64), .LIMB(12)) co12   (.a(a64), .b(b64), .p(p_co12));
  karatsuba_mul #(.N(53), .BASE(18)) ka18_53 (.a(a53), .b(b53), .p(p53_ka18));
  karatsuba_mul #(.N(53), .BASE(17)) ka17_53 (.a(a53), .b(b53), .p(p53_ka17));
  comba_mul     #(.N(53), .LIMB(16)) co16_53 (.a(a53), .b(b53), .p(p53_co16));
  comba_mul     #(.N(53), .LIMB(17)) co17_53 (.a(a53), .b(b53), .p(p53_co17));

  task check;
    begin
      #1;
      exp64 = a64 * b64;
      exp53 = a53 * b53;
      n = n + 1;
      if ({p_ka18, p_ka17, p_ka9, p_co16, p_co17, p_co12} !== {6{exp64}} ||
          {p53_ka18, p53_ka17, p53_co16, p53_co17} !== {4{exp53}}) begin
        err = err + 1;
        if (err <= 10)
          $display("MISMATCH a=%h b=%h exp=%h ka18=%h ka17=%h ka9=%h co16=%h co17=%h co12=%h | 53b exp=%h ka18=%h ka17=%h co16=%h co17=%h",
                   a64, b64, exp64, p_ka18, p_ka17, p_ka9, p_co16, p_co17, p_co12, exp53, p53_ka18, p53_ka17, p53_co16, p53_co17);
      end
    end
  endtask

  reg [63:0] corner [0:11];

  initial begin
    corner[0]  = 64'd0;                 corner[1]  = 64'd1;
    corner[2]  = 64'hFFFF_FFFF_FFFF_FFFF; corner[3]  = 64'h8000_0000_0000_0000;
    corner[4]  = 64'h7FFF_FFFF_FFFF_FFFF; corner[5]  = 64'h001F_FFFF_FFFF_FFFF; // 53 ones
    corner[6]  = 64'h0010_0000_0000_0000; corner[7]  = 64'hAAAA_AAAA_AAAA_AAAA;
    corner[8]  = 64'h5555_5555_5555_5555; corner[9]  = 64'h0000_0000_FFFF_FFFF;
    corner[10] = 64'hFFFF_FFFF_0000_0000; corner[11] = 64'h001F_FFFF_0000_FFFF;
    for (i = 0; i < 12; i = i + 1)
      for (j = 0; j < 12; j = j + 1) begin
        a64 = corner[i]; b64 = corner[j]; check;
      end
    for (i = 0; i < 64; i = i + 1)           // single bits and all-ones prefixes
      for (j = 0; j < 64; j = j + 1) begin
        a64 = 64'd1 << i; b64 = ~(64'd0) >> j; check;
      end
    for (i = 0; i < NUM_RANDOM; i = i + 1) begin
      a64 = {$urandom, $urandom}; b64 = {$urandom, $urandom};
      if (i % 4 == 1) a64 = a64 | 64'hFFFF_0000_0000_0000;
      if (i % 4 == 2) b64 = ~(b64 & 64'h0000_0000_0000_FFFF);
      if (i % 4 == 3) begin a64[52] = 1'b1; b64[52] = 1'b1; end // mantissa-like
      check;
    end
    $display("mult_check: checked %0d vectors, %0d errors -> %s", n, err, (err == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
