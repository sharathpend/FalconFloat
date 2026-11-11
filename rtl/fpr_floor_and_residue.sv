
`include "defines.vh"

// floor(x) as a signed int64, and the residue r = x - floor(x) as a double,
// in one pass. Bit-exact to FALCON's
//     s = fpr_floor(x);  r = fpr_sub(x, fpr_of(s));
// without an int-to-double converter or a full adder.
//
// How:
//   1. One left shift splits |x| into a 64-bit integer part and an exact 53-bit
//      fraction (the same decomposition as fpr_round).
//   2. x >= 0: floor = int,       r = frac
//      x <  0: floor = -int - 1,  r = 1 - frac   (if frac != 0)
//              floor = -int,      r = 0          (if frac == 0)
//      "1 - frac" is a two's complement of the fraction bits.
//   3. Normalize r (leading-one + shift) to pack it as a double.
//
// r is exact everywhere except -0.5 < x < 0, where r = 1 - |x| and |x| has
// bits below 2^-53. That case aligns |x| with a sticky bit (like fpr_add) and
// rounds to nearest even; r can round up to exactly 1.0, as fpr_sub would.
// For 0 <= x < 0.5, r = x and the input is passed through unchanged.
//
// Scope: inputs are +/-0 or normal with |x| < 2^63 (or x = -2^63). For |x| >= 2^63
// the floor saturates and r = +0. An exponent of 0 is treated as zero.
module fpr_floor_and_residue #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_floor_and_residue_in_tvalid,
  input  wire [63:0]  fpr_floor_and_residue_in_tdata,

  output wire         fpr_floor_and_residue_out_tvalid,
  output wire [63:0]  fpr_floor_and_residue_out_floor,    // signed int64
  output wire [63:0]  fpr_floor_and_residue_out_residue   // double in [0, 1]
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

  // Small negative inputs (-0.5 < x < 0): align |x| to 56 fraction bits with sticky
  wire [10:0]  small_shift;             // 1022 - exp, >= 1
  wire [55:0]  small_sig;               // {1.mant, G, R, S} = |x| * 2^56 when exp = 1022
  wire [55:0]  small_shifted;
  wire [55:0]  small_shifted_out_mask;
  wire         small_sticky;
  wire [55:0]  small_aligned;

  // Residue back end: fixed point with 56 fraction bits, value = res_fixed * 2^-56
  wire         use_small_path;
  wire [55:0]  res_operand;
  wire         res_negate;              // compute 1 - operand instead of operand
  wire [56:0]  res_fixed_full;
  wire [55:0]  res_fixed;               // always < 1.0, so bit 56 is never needed
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

  wire [63:0]  out_floor;
  wire [63:0]  out_residue;

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         fpr_floor_and_residue_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_floor_and_residue_out_floor_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_floor_and_residue_out_residue_reg = 0;
  `else
    (* dont_touch = "true" *) reg         fpr_floor_and_residue_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_floor_and_residue_out_floor_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_floor_and_residue_out_residue_reg;
  `endif

  assign in1_sign          = fpr_floor_and_residue_in_tdata[63];
  assign in1_exp           = fpr_floor_and_residue_in_tdata[62:52];
  assign in1_mant          = fpr_floor_and_residue_in_tdata[51:0];
  assign in1_mant_extended = {1'b1, in1_mant};

  assign in1_is_zero             = (in1_exp == 11'd0);
  assign in1_lt_half             = (in1_exp < 11'd1022);
  assign in1_out_of_int64_bounds = (in1_exp >= 11'd1086);

  // ---------------------------------------------------------------------------
  // 1. Decompose |x| = int_part + frac_part * 2^-53   (exact for exp 1022..1085)
  // ---------------------------------------------------------------------------
  assign decomp_shift_full = in1_exp - 11'd1022;
  assign decomp_shift      = decomp_shift_full[5:0];
  assign decomp_fixed      = {64'd0, in1_mant_extended} << decomp_shift;
  assign int_part          = decomp_fixed[116:53];
  assign frac_part         = decomp_fixed[52:0];
  assign frac_is_nonzero   = |frac_part;

  // ---------------------------------------------------------------------------
  // 2a. Floor
  //   -int - 1 = ~int, so a negative input with a fraction needs no adder.
  // ---------------------------------------------------------------------------
  assign out_floor = in1_lt_half             ? ((in1_sign & ~in1_is_zero) ? 64'hFFFF_FFFF_FFFF_FFFF : 64'd0) :
                     in1_out_of_int64_bounds ? (in1_sign ? 64'h8000_0000_0000_0000 : 64'h7FFF_FFFF_FFFF_FFFF) :
                     ~in1_sign               ? int_part :
                     frac_is_nonzero         ? ~int_part :
                                               ((~int_part) + 64'd1);

  // ---------------------------------------------------------------------------
  // 2b. Residue operand
  //   |x| >= 0.5 : operand = frac_part (exact, low 3 bits zero)
  //   |x| <  0.5, x < 0 : operand = |x| aligned to 2^-56 with sticky
  // ---------------------------------------------------------------------------
  assign small_shift            = 11'd1022 - in1_exp;
  assign small_sig              = {in1_mant_extended, 3'b000};
  assign small_shifted          = (small_shift >= 11'd56) ? 56'd0 : (small_sig >> small_shift[5:0]);
  assign small_shifted_out_mask = (small_shift >= 11'd56) ? {56{1'b1}} : ~({56{1'b1}} << small_shift[5:0]);
  assign small_sticky           = |(small_sig & small_shifted_out_mask);
  assign small_aligned          = {small_shifted[55:1], small_shifted[0] | small_sticky};

  assign use_small_path = in1_lt_half;
  assign res_operand    = use_small_path ? small_aligned : {frac_part, 3'b000};
  assign res_negate     = in1_sign;

  // r = operand, or 1 - operand for negative x. 1.0 = 2^56 in this fixed point.
  assign res_fixed_full = res_negate ? ({1'b1, 56'd0} - {1'b0, res_operand}) : {1'b0, res_operand};
  // When negating, a zero operand would give exactly 1.0, but that case is the
  // "x is a negative integer" case and r = 0 there, so it is excluded below.
  assign res_fixed      = res_fixed_full[55:0];
  assign res_is_zero    = (res_operand == 56'd0);

  // ---------------------------------------------------------------------------
  // 3. Normalize and round (rounding only ever triggers on the small path)
  // ---------------------------------------------------------------------------
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

  // Leading one at res_fixed bit p (= loc - 8) has weight 2^(p - 56),
  // so the biased exponent is 1023 + p - 56 = 959 + loc. +1 if rounding carried out
  // (only possible on the small path, giving exactly 1.0).
  assign res_exp = 11'd959 + {5'd0, res_lead_one_loc} + {10'd0, res_mant_rounded[52]};

  assign out_residue = in1_out_of_int64_bounds        ? 64'd0 :                           // x is an integer
                       (in1_lt_half & ~in1_sign)      ? fpr_floor_and_residue_in_tdata :  // 0 <= x < 0.5: r = x
                       in1_is_zero                    ? fpr_floor_and_residue_in_tdata :  // -0: r = -0
                       res_is_zero                    ? 64'd0 :                           // x is an integer: r = +0
                                                        {1'b0, res_exp, res_mant_rounded[51:0]};

  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_floor_and_residue_out_tvalid_reg  <= 1'b0;
      fpr_floor_and_residue_out_floor_reg   <= 64'd0;
      fpr_floor_and_residue_out_residue_reg <= 64'd0;
    end else begin
      fpr_floor_and_residue_out_tvalid_reg  <= fpr_floor_and_residue_in_tvalid;
      fpr_floor_and_residue_out_floor_reg   <= out_floor;
      fpr_floor_and_residue_out_residue_reg <= out_residue;
    end
  end

  assign fpr_floor_and_residue_out_tvalid  = fpr_floor_and_residue_out_tvalid_reg;
  assign fpr_floor_and_residue_out_floor   = fpr_floor_and_residue_out_floor_reg;
  assign fpr_floor_and_residue_out_residue = fpr_floor_and_residue_out_residue_reg;

endmodule
