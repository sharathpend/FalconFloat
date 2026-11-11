//=====================================================
// Designer: Sharath Pendyala
// email: spendya@ncsu.edu, sharathpawan@gmail.com
//=====================================================

// Double to signed int64, round to nearest, ties to even (FALCON fpr_rint).
// Inputs with |x| >= 2^63 saturate to 0x7FFF_FFFF_FFFF_FFFF / 0x8000_0000_0000_0000
// (-2^63 itself is exact). An exponent of 0 is treated as zero.
`include "defines.vh"

module fpr_round #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_round_in_tvalid,
  input  wire [63:0]  fpr_round_in_tdata,

  output wire         fpr_round_out_tvalid,
  output wire [63:0]  fpr_round_out_tdata
);

  wire         in1_sign;
  wire [10:0]  in1_exp;
  wire [51:0]  in1_mant;
  wire [52:0]  in1_mant_extended;
  wire         in1_lt_half;             // |x| < 0.5 (includes zero) -> rounds to 0
  wire         in1_out_of_int64_bounds; // |x| >= 2^63 -> saturate

  wire [10:0]  decomp_shift_full;
  wire [5:0]  decomp_shift;            // exp - 1022, valid range 0..63
  wire [116:0] decomp_fixed;            // fixed point: [116:53] integer, [52:0] fraction
  wire [63:0]  int_part;
  wire [52:0]  frac_part;

  wire         guard_bit;
  wire         sticky_bit;
  wire         round_up;
  wire [63:0]  mag_rounded;
  wire [63:0]  out_int;

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         fpr_round_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_round_out_tdata_reg = 0;
  `else
    (* dont_touch = "true" *) reg         fpr_round_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_round_out_tdata_reg;
  `endif

  assign in1_sign          = fpr_round_in_tdata[63];
  assign in1_exp           = fpr_round_in_tdata[62:52];
  assign in1_mant          = fpr_round_in_tdata[51:0];
  assign in1_mant_extended = {1'b1, in1_mant};

  // Compare the biased exponent directly, so no signed arithmetic is needed.
  assign in1_lt_half             = (in1_exp < 11'd1022);  // exp - 1023 < -1
  assign in1_out_of_int64_bounds = (in1_exp >= 11'd1086); // exp - 1023 >= 63

  // Decompose |x| into integer and fraction with one left shift.
  // {64'b0, 1.mant} with the binary point at bit 53 has value 1.mant * 2^-1,
  // i.e. it is x for exp = 1022. Shifting left by (exp - 1022) gives |x| for
  // any exp in 1022..1085. Everything the fraction can hold is kept exactly,
  // because the lowest mantissa bit weighs 2^(e-52) >= 2^-53 in that range.
  assign decomp_shift_full = in1_exp - 11'd1022;
  assign decomp_shift      = decomp_shift_full[5:0];
  assign decomp_fixed      = {64'd0, in1_mant_extended} << decomp_shift;
  assign int_part          = decomp_fixed[116:53];
  assign frac_part         = decomp_fixed[52:0];

  // Round to nearest, ties to even
  //   G=0           -> fraction < 0.5, keep
  //   G=1, S=1      -> fraction > 0.5, round up
  //   G=1, S=0      -> fraction = 0.5 exactly, round up only if the integer is odd
  assign guard_bit   = frac_part[52];
  assign sticky_bit  = |frac_part[51:0];
  assign round_up    = guard_bit & (sticky_bit | int_part[0]);
  // No overflow possible: a fraction only exists for |x| < 2^52.
  assign mag_rounded = int_part + {63'd0, round_up};

  assign out_int = in1_lt_half             ? 64'd0 :
                   in1_out_of_int64_bounds ? (in1_sign ? 64'h8000_0000_0000_0000 : 64'h7FFF_FFFF_FFFF_FFFF) :
                   in1_sign                ? ((~mag_rounded) + 64'd1) :
                                             mag_rounded;

  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_round_out_tvalid_reg <= 1'b0;
      fpr_round_out_tdata_reg  <= 64'd0;
    end else begin
      fpr_round_out_tvalid_reg <= fpr_round_in_tvalid;
      fpr_round_out_tdata_reg  <= out_int;
    end
  end

  assign fpr_round_out_tvalid = fpr_round_out_tvalid_reg;
  assign fpr_round_out_tdata  = fpr_round_out_tdata_reg;

endmodule
