
`include "defines.vh"

// Normalize, round to nearest even, and pack the adder result.
//
// sum layout (57 bits):  [56] carry  [55] hidden  [54:3] mantissa  [2] G  [1] R  [0] S
//
// One left shift handles every case:
//   carry out (effective add overflow)  -> shift 0, the old R|S fold into S
//   normal                               -> shift 1
//   cancellation (effective sub)         -> shift 2..56; this only happens when
//                                           the exponent gap was 0 or 1, so the
//                                           low bits are exact and nothing is lost
// After the shift the leading 1 is at bit 56, so the mantissa, G, R and S
// always sit at the same positions.
module fpr_add_norm #(
  parameter DEBUG = 0
) (
  input  wire [56:0] sum,
  input  wire [10:0] big_exp,
  input  wire        result_sign,
  input  wire        zero_sign,    // sign to use when the result is exactly zero
  output wire [63:0] result
);

  wire        sum_is_zero;
  wire [5:0]  lead_one_loc;
  wire [5:0]  lz;                  // leading zeros of the 57-bit sum
  wire [56:0] norm;

  wire [52:0] mant_truncated;      // hidden bit + 52-bit mantissa
  wire        guard_bit;
  wire        round_bit;
  wire        sticky_bit;
  wire        round_up;
  wire [53:0] mant_rounded;        // bit 53 = carry out of rounding
  wire        mant_round_ovf;

  wire [10:0] exp_final;

  assign sum_is_zero = (sum == 57'd0);

  // Reuse the leading-one finder: pad the 57-bit sum to 64 bits at the bottom,
  // so bit 56 of sum maps to bit 63 of the finder input.
  leading_one_calc #(
    .DEBUG (DEBUG),
    .N (64),
    .N_BITS (6)
  ) leading_one_calc_inst (
    .loc_din  ({sum, 7'd0}),
    .loc_dout (lead_one_loc)
  );

  assign lz   = 6'd63 - lead_one_loc;
  assign norm = sum << lz;

  assign mant_truncated = norm[56:4];
  assign guard_bit      = norm[3];
  assign round_bit      = norm[2];
  assign sticky_bit     = |norm[1:0];

  // Round to nearest, ties to even
  assign round_up = guard_bit & (round_bit | sticky_bit | mant_truncated[0]);

  assign mant_rounded   = {1'b0, mant_truncated} + {53'd0, round_up};
  assign mant_round_ovf = mant_rounded[53];  // 1.111..1 + ulp = 10.000..0; mantissa field becomes 0

  // carry case (lz = 0) -> big_exp + 1, normal (lz = 1) -> big_exp, cancellation -> smaller.
  // 11-bit arithmetic is enough: the result is assumed to stay in the normal range.
  assign exp_final = big_exp + 11'd1 - {5'd0, lz} + {10'd0, mant_round_ovf};

  assign result = sum_is_zero ? {zero_sign, 63'd0} :   // exact zero (e.g. x + (-x))
                                {result_sign, exp_final, mant_rounded[51:0]};

endmodule
