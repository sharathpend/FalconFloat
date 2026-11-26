
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`include "defines.vh"

// ceil(x) as a signed int64, and r = x - ceil(x) as a double (r in [-1, 0]).
// Matches  s = ceil(x);  r = fpr_sub(x, fpr_of(s)).  Mirror of fpr_floor_and_residue:
//   x >= 0: ceil = int + 1, r = -(1 - frac)   (if frac != 0)
//   x <  0: ceil = -int,    r = -frac
//   frac == 0: r = +0
// r is exact everywhere except 0 < x < 0.5, where r = -(1 - x) is rounded to
// nearest even (and can round to exactly -1.0). For -0.5 < x <= 0, r = x.
// Scope: inputs are +/-0 or normal. For |x| >= 2^63 the ceil saturates and r = +0.
// An exponent of 0 is treated as zero.
module fpr_ceil_and_residue #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_ceil_and_residue_in_tvalid,
  input  wire [63:0]  fpr_ceil_and_residue_in_tdata,

  output wire         fpr_ceil_and_residue_out_tvalid,
  output wire [63:0]  fpr_ceil_and_residue_out_ceil,     // signed int64
  output wire [63:0]  fpr_ceil_and_residue_out_residue   // double in [-1, 0]
);

  wire         in1_sign;
  wire [10:0]  in1_exp;
  wire [51:0]  in1_mant;
  wire [52:0]  in1_mant_extended;
  wire         in1_is_zero;             // exp == 0
  wire         in1_lt_half;             // |x| < 0.5 (includes zero)
  wire         in1_out_of_int64_bounds; // |x| >= 2^63

  // Decomposition (|x| >= 0.5)
  wire [10:0]  decomp_shift_full;
  wire [5:0]   decomp_shift;            // exp - 1022, valid range 0..63
  wire [116:0] decomp_fixed;            // [116:53] integer, [52:0] fraction
  wire [63:0]  int_part;
  wire [52:0]  frac_part;
  wire         frac_is_nonzero;

  wire [63:0]  ceil_addend;
  wire         ceil_carry_in;
  wire [63:0]  ceil_sum;

  // Small positive inputs (0 < x < 0.5): align x to 56 fraction bits with sticky
  wire [10:0]  small_shift;             // 1022 - exp, >= 1
  wire [55:0]  small_sig;               // {1.mant, G, R, S}
  wire [55:0]  small_shifted;
  wire [55:0]  small_shifted_out_mask;
  wire         small_sticky;
  wire [55:0]  small_aligned;

  // Residue magnitude: fixed point with 56 fraction bits, value = res_fixed * 2^-56
  wire         use_small_path;
  wire [55:0]  res_operand;
  wire         res_negate;              // magnitude is 1 - operand instead of operand
  wire [56:0]  res_fixed_full;
  wire [55:0]  res_fixed;
  wire         res_is_zero;

  wire [5:0]   res_lead_one_loc;
  wire [63:0]  res_norm;                // leading 1 at bit 63
  wire [51:0]  res_mant_truncated;
  wire         res_guard_bit;
  wire         res_round_bit;
  wire         res_sticky_bit;
  wire         res_round_up;
  wire [52:0]  res_mant_rounded;        // bit 52 = carry out of rounding
  wire [10:0]  res_exp;

  wire [63:0]  out_ceil;
  wire [63:0]  out_residue;

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         fpr_ceil_and_residue_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_ceil_and_residue_out_ceil_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_ceil_and_residue_out_residue_reg = 0;
  `else
    (* dont_touch = "true" *) reg         fpr_ceil_and_residue_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_ceil_and_residue_out_ceil_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_ceil_and_residue_out_residue_reg;
  `endif

  assign in1_sign          = fpr_ceil_and_residue_in_tdata[63];
  assign in1_exp           = fpr_ceil_and_residue_in_tdata[62:52];
  assign in1_mant          = fpr_ceil_and_residue_in_tdata[51:0];
  assign in1_mant_extended = {1'b1, in1_mant};

  assign in1_is_zero             = (in1_exp == 11'd0);
  assign in1_lt_half             = (in1_exp < 11'd1022);
  assign in1_out_of_int64_bounds = (in1_exp >= 11'd1086);

  // 1. Decompose |x| = int_part + frac_part * 2^-53   (exact for exp 1022..1085)
  assign decomp_shift_full = in1_exp - 11'd1022;
  assign decomp_shift      = decomp_shift_full[5:0];
  assign decomp_fixed      = {64'd0, in1_mant_extended} << decomp_shift;
  assign int_part          = decomp_fixed[116:53];
  assign frac_part         = decomp_fixed[52:0];
  assign frac_is_nonzero   = |frac_part;

  // 2a. Ceil
  assign ceil_addend   = in1_sign ? ~int_part : int_part;
  assign ceil_carry_in = in1_sign | frac_is_nonzero;
  assign ceil_sum      = ceil_addend + {63'd0, ceil_carry_in};

  assign out_ceil = in1_lt_half             ? {63'd0, ~in1_sign & ~in1_is_zero} :
                    in1_out_of_int64_bounds ? (in1_sign ? 64'h8000_0000_0000_0000 : 64'h7FFF_FFFF_FFFF_FFFF) :
                                              ceil_sum;

  // 2b. Residue operand
  assign small_shift            = 11'd1022 - in1_exp;
  assign small_sig              = {in1_mant_extended, 3'b000};
  assign small_shifted          = (small_shift >= 11'd56) ? 56'd0 : (small_sig >> small_shift[5:0]);
  assign small_shifted_out_mask = (small_shift >= 11'd56) ? {56{1'b1}} : ~({56{1'b1}} << small_shift[5:0]);
  assign small_sticky           = |(small_sig & small_shifted_out_mask);
  assign small_aligned          = {small_shifted[55:1], small_shifted[0] | small_sticky};

  assign use_small_path = in1_lt_half;
  assign res_operand    = use_small_path ? small_aligned : {frac_part, 3'b000};
  assign res_negate     = ~in1_sign;

  assign res_fixed_full = res_negate ? ({1'b1, 56'd0} - {1'b0, res_operand}) : {1'b0, res_operand};
  assign res_fixed      = res_fixed_full[55:0];
  assign res_is_zero    = (res_operand == 56'd0);

  // 3. Normalize and round (rounding only ever triggers on the small path)
  leading_one_calc #(
    .DEBUG (DEBUG),
    .N (64),
    .N_BITS (6)
  ) leading_one_calc_inst (
    .loc_din  ({res_fixed, 8'd0}),
    .loc_dout (res_lead_one_loc)
  );

  assign res_norm           = {res_fixed, 8'd0} << (6'd63 - res_lead_one_loc);
  assign res_mant_truncated = res_norm[62:11];
  assign res_guard_bit      = res_norm[10];
  assign res_round_bit      = res_norm[9];
  assign res_sticky_bit     = |res_norm[8:0];
  assign res_round_up       = res_guard_bit & (res_round_bit | res_sticky_bit | res_mant_truncated[0]);
  assign res_mant_rounded   = {1'b0, res_mant_truncated} + {52'd0, res_round_up};

  assign res_exp = 11'd959 + {5'd0, res_lead_one_loc} + {10'd0, res_mant_rounded[52]};

  assign out_residue = in1_out_of_int64_bounds        ? 64'd0 :                          // x is an integer
                       (in1_lt_half & in1_sign)       ? fpr_ceil_and_residue_in_tdata :  // -0.5 < x <= -0: r = x
                       in1_is_zero                    ? fpr_ceil_and_residue_in_tdata :  // +0: r = +0
                       res_is_zero                    ? 64'd0 :                          // x is an integer: r = +0
                                                        {1'b1, res_exp, res_mant_rounded[51:0]};

  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_ceil_and_residue_out_tvalid_reg  <= 1'b0;
      fpr_ceil_and_residue_out_ceil_reg    <= 64'd0;
      fpr_ceil_and_residue_out_residue_reg <= 64'd0;
    end else begin
      fpr_ceil_and_residue_out_tvalid_reg  <= fpr_ceil_and_residue_in_tvalid;
      fpr_ceil_and_residue_out_ceil_reg    <= out_ceil;
      fpr_ceil_and_residue_out_residue_reg <= out_residue;
    end
  end

  assign fpr_ceil_and_residue_out_tvalid  = fpr_ceil_and_residue_out_tvalid_reg;
  assign fpr_ceil_and_residue_out_ceil    = fpr_ceil_and_residue_out_ceil_reg;
  assign fpr_ceil_and_residue_out_residue = fpr_ceil_and_residue_out_residue_reg;

endmodule
