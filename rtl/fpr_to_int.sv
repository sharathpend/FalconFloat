
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`include "defines.vh"

// Shared double -> integer rounding, one unit for all modes:
//   mode 2'b00 = floor, 2'b01 = ceil, 2'b10 = trunc, 2'b11 = round (nearest, ties to even)
// Outputs (1-cycle latency):
//   out_int     = rounded value as a signed int64 (FALCON fpr_floor / fpr_trunc / fpr_rint)
//   out_fpr     = rounded value as a double, = fpr_of(out_int) (x itself for |x| >= 2^63)
//   out_residue = x - out_fpr as a double, = fpr_sub(x, fpr_of(out_int))
// One decomposition |x| = I + F * 2^-53 serves every mode. The mode only decides
// whether the magnitude goes up by one ("up"):
//   floor: sign & (F != 0)   ceil: ~sign & (F != 0)   trunc: 0   round: G & (S | I[0])
// then  int = (sign ? ~I : I) + (sign ? ~up : up)   (one adder, = sign ? -(I + up) : I + up)
//       residue = (sign ^ up) * (up ? 1 - F : F), exact except for |x| < 0.5 with up = 1,
//       where 1 - |x| is rounded to nearest even (sticky alignment, as in fpr_floor_and_residue).
// Replaces fpr_floor, fpr_ceil, fpr_trunc, fpr_round and the *_and_residue variants
// with one shifter, one incrementer and one residue normalizer. Results match them
// bit for bit in their scope.
// FPR_OUT = 0 / RESIDUE_OUT = 0 remove those outputs' logic (outputs tied to 0).
// out_int: any input. |x| >= 2^63, Inf and NaN saturate by sign. Subnormals are
//   handled as the tiny values they are (floor(-tiny) = -1, ceil(+tiny) = 1).
// out_fpr, out_residue: same, with r = +0 for |x| >= 2^63.
module fpr_to_int #(
  parameter DEBUG       = 0,
  parameter FPR_OUT     = 1,
  parameter RESIDUE_OUT = 1
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_to_int_in_tvalid,
  input  wire [63:0]  fpr_to_int_in_tdata,
  input  wire [1:0]   fpr_to_int_mode,         // 00 floor, 01 ceil, 10 trunc, 11 round

  output wire         fpr_to_int_out_tvalid,
  output wire [63:0]  fpr_to_int_out_int,      // signed int64
  output wire [63:0]  fpr_to_int_out_fpr,      // double
  output wire [63:0]  fpr_to_int_out_residue   // double, x - out_fpr
);

  localparam MODE_FLOOR = 2'b00;
  localparam MODE_CEIL  = 2'b01;
  localparam MODE_TRUNC = 2'b10;
  localparam MODE_ROUND = 2'b11;

  wire         in1_sign;
  wire [10:0]  in1_exp;
  wire [51:0]  in1_mant;
  wire [52:0]  in1_mant_extended;
  wire         in1_is_zero;             // +/-0
  wire         in1_lt_half;             // |x| < 0.5
  wire         in1_lt_one;              // |x| < 1
  wire         in1_is_int;              // |x| >= 2^52, no fraction bits
  wire         in1_out_of_int64_bounds; // |x| >= 2^63

  // Decomposition (|x| >= 0.5)
  wire [10:0]  decomp_shift_full;
  wire [5:0]   decomp_shift;            // exp - 1022, valid range 0..63
  wire [116:0] decomp_fixed;            // [116:53] integer, [52:0] fraction
  wire [63:0]  int_part;                // I (0 for |x| < 0.5)
  wire [52:0]  frac_part;               // F
  wire         frac_is_nonzero;
  wire         guard_bit;               // F >= 0.5
  wire         sticky_bit;              // F has bits below 0.5
  reg          up;                      // round the magnitude up by one

  wire [63:0]  out_int;
  wire [63:0]  out_fpr;
  wire [63:0]  out_residue;

  assign in1_sign          = fpr_to_int_in_tdata[63];
  assign in1_exp           = fpr_to_int_in_tdata[62:52];
  assign in1_mant          = fpr_to_int_in_tdata[51:0];
  assign in1_mant_extended = {1'b1, in1_mant};

  assign in1_is_zero             = (in1_exp == 11'd0) && (in1_mant == 52'd0);
  assign in1_lt_half             = (in1_exp < 11'd1022);
  assign in1_lt_one              = (in1_exp < 11'd1023);
  assign in1_is_int              = (in1_exp >= 11'd1075);
  assign in1_out_of_int64_bounds = (in1_exp >= 11'd1086);

  assign decomp_shift_full = in1_exp - 11'd1022;
  assign decomp_shift      = decomp_shift_full[5:0];
  assign decomp_fixed      = {64'd0, in1_mant_extended} << decomp_shift;
  assign int_part          = in1_lt_half ? 64'd0 : decomp_fixed[116:53];
  assign frac_part         = decomp_fixed[52:0];
  assign frac_is_nonzero   = in1_lt_half ? ~in1_is_zero : (|frac_part);
  assign guard_bit         = in1_lt_half ? 1'b0 : frac_part[52];
  assign sticky_bit        = in1_lt_half ? ~in1_is_zero : (|frac_part[51:0]);

  always@ (*) begin
    case (fpr_to_int_mode)
      MODE_FLOOR: up = in1_sign & frac_is_nonzero;
      MODE_CEIL:  up = ~in1_sign & frac_is_nonzero;
      MODE_TRUNC: up = 1'b0;
      default:    up = guard_bit & (sticky_bit | int_part[0]);
    endcase
  end

  // ---------------------------------------------------------------------------
  // int64. No overflow: a fraction only exists for |x| < 2^52.
  // ---------------------------------------------------------------------------
  assign out_int = in1_out_of_int64_bounds ? (in1_sign ? 64'h8000_0000_0000_0000 : 64'h7FFF_FFFF_FFFF_FFFF) :
                   ((in1_sign ? ~int_part : int_part) + {63'd0, in1_sign ^ up});

  // ---------------------------------------------------------------------------
  // Double value: clear the fraction bits, plus one integer ulp when up
  // ---------------------------------------------------------------------------
  generate
    if (FPR_OUT) begin : gen_fpr_out
      wire [10:0] frac_shift_full;
      wire [5:0]  frac_shift;          // exp - 1023, valid range 0..51
      wire [51:0] frac_mask;           // 1s on the fraction bits of the mantissa
      wire [51:0] mant_int_bits;
      wire [52:0] int_ulp;             // weight 2^0 in {1.mant}
      wire [53:0] mag_plus_one;        // {1.mant_int_bits} + 1, bit 53 = carry
      wire [10:0] mag_plus_one_exp;

      assign frac_shift_full  = in1_exp - 11'd1023;
      assign frac_shift       = frac_shift_full[5:0];
      assign frac_mask        = {52{1'b1}} >> frac_shift;
      assign mant_int_bits    = in1_mant & ~frac_mask;
      assign int_ulp          = {frac_mask, 1'b1} & ~{1'b0, frac_mask};
      assign mag_plus_one     = {2'b01, mant_int_bits} + {1'b0, int_ulp};
      assign mag_plus_one_exp = in1_exp + {10'd0, mag_plus_one[53]};

      assign out_fpr = in1_lt_one ? (up ? {in1_sign, 11'd1023, 52'd0} : 64'd0) : // +/-1.0 or +0
                       in1_is_int ? fpr_to_int_in_tdata :
                       up         ? {in1_sign, mag_plus_one_exp, mag_plus_one[51:0]} :
                                    {in1_sign, in1_exp, mant_int_bits};
    end else begin : gen_no_fpr_out
      assign out_fpr = 64'd0;
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Residue r = x - rounded, fixed point with 56 fraction bits
  // ---------------------------------------------------------------------------
  generate
    if (RESIDUE_OUT) begin : gen_residue_out
      // |x| < 0.5: align |x| to 2^-56 with sticky (only used with up = 1)
      wire [10:0] small_shift;         // 1022 - exp, >= 1
      wire [55:0] small_sig;           // {1.mant, G, R, S}
      wire [55:0] small_shifted;
      wire [55:0] small_shifted_out_mask;
      wire        small_sticky;
      wire [55:0] small_aligned;

      wire [55:0] res_operand;
      wire [56:0] res_fixed_full;
      wire [55:0] res_fixed;           // < 1.0 before rounding
      wire        res_is_zero;

      wire [5:0]  res_lead_one_loc;
      wire [63:0] res_norm;            // leading 1 at bit 63
      wire [51:0] res_mant_truncated;
      wire        res_guard_bit;
      wire        res_round_bit;
      wire        res_sticky_bit;
      wire        res_round_up;
      wire [52:0] res_mant_rounded;    // bit 52 = carry out of rounding
      wire [10:0] res_exp;

      assign small_shift            = 11'd1022 - in1_exp;
      assign small_sig              = {in1_mant_extended, 3'b000};
      assign small_shifted          = (small_shift >= 11'd56) ? 56'd0 : (small_sig >> small_shift[5:0]);
      assign small_shifted_out_mask = (small_shift >= 11'd56) ? {56{1'b1}} : ~({56{1'b1}} << small_shift[5:0]);
      assign small_sticky           = |(small_sig & small_shifted_out_mask);
      assign small_aligned          = {small_shifted[55:1], small_shifted[0] | small_sticky};

      // |r| = up ? 1 - F : F.  1.0 = 2^56 here, and up = 1 implies F != 0.
      assign res_operand    = in1_lt_half ? small_aligned : {frac_part, 3'b000};
      assign res_fixed_full = up ? ({1'b1, 56'd0} - {1'b0, res_operand}) : {1'b0, res_operand};
      assign res_fixed      = res_fixed_full[55:0];
      assign res_is_zero    = (res_operand == 56'd0);

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
      // Leading one at res_fixed bit (loc - 8), weight 2^(loc - 64): exp = 959 + loc (+1 on carry)
      assign res_exp            = 11'd959 + {5'd0, res_lead_one_loc} + {10'd0, res_mant_rounded[52]};

      assign out_residue = in1_out_of_int64_bounds ? 64'd0 :                    // x is an integer
                           (in1_lt_half & ~up)     ? fpr_to_int_in_tdata :      // rounded = 0: r = x (incl. +/-0)
                           res_is_zero             ? 64'd0 :                    // x is an integer: r = +0
                                                     {in1_sign ^ up, res_exp, res_mant_rounded[51:0]};
    end else begin : gen_no_residue_out
      assign out_residue = 64'd0;
    end
  endgenerate

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         fpr_to_int_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_to_int_out_int_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_to_int_out_fpr_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_to_int_out_residue_reg = 0;
  `else
    (* dont_touch = "true" *) reg         fpr_to_int_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_to_int_out_int_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_to_int_out_fpr_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_to_int_out_residue_reg;
  `endif

  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_to_int_out_tvalid_reg  <= 1'b0;
      fpr_to_int_out_int_reg     <= 64'd0;
      fpr_to_int_out_fpr_reg     <= 64'd0;
      fpr_to_int_out_residue_reg <= 64'd0;
    end else begin
      fpr_to_int_out_tvalid_reg  <= fpr_to_int_in_tvalid;
      fpr_to_int_out_int_reg     <= out_int;
      fpr_to_int_out_fpr_reg     <= out_fpr;
      fpr_to_int_out_residue_reg <= out_residue;
    end
  end

  assign fpr_to_int_out_tvalid  = fpr_to_int_out_tvalid_reg;
  assign fpr_to_int_out_int     = fpr_to_int_out_int_reg;
  assign fpr_to_int_out_fpr     = fpr_to_int_out_fpr_reg;
  assign fpr_to_int_out_residue = fpr_to_int_out_residue_reg;

endmodule
