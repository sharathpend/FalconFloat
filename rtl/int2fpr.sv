//=====================================================
// Designer: Sharath Pendyala
// 
//=====================================================

// Signed Int64 to FPR (IEEE-754 binary64), round-to-nearest-even
`include "defines.vh"

module int2fpr #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         int2fpr_in_tvalid,
  input  wire [63:0]  int2fpr_in_tdata,

  output wire         int2fpr_out_tvalid,
  output wire [63:0]  int2fpr_out_tdata
);

  wire        in_tdata_is_0;
  wire [63:0] in_unsigned;
  wire [5:0]  in_unsigned_loc;

  wire [5:0]  norm_shift_amount;
  wire [63:0] in_normalized;     // leading 1 moved to bit 63

  wire [51:0] mant_truncated;
  wire        guard_bit;
  wire        round_bit;
  wire        sticky_bit;
  wire        round_up;
  wire [52:0] mant_rounded;      // bit 52 = carry out of rounding
  wire        mant_round_ovf;

  wire        out_sign;
  wire [10:0] out_exp;
  wire [51:0] out_mant;

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         int2fpr_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] int2fpr_out_tdata_reg = 0;
  `else
    (* dont_touch = "true" *) reg         int2fpr_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] int2fpr_out_tdata_reg;
  `endif

  // signed to unsigned (magnitude) conversion.
  // No special case is needed for the most negative value: in 64 bits,
  // ~(0x8000_0000_0000_0000) + 1 = 0x8000_0000_0000_0000, which read as
  // unsigned is exactly 2^63, the correct magnitude.
  assign in_unsigned   = int2fpr_in_tdata[63] ? ((~int2fpr_in_tdata) + 64'd1) : int2fpr_in_tdata;
  assign in_tdata_is_0 = (int2fpr_in_tdata == 64'd0);
  assign out_sign      = int2fpr_in_tdata[63];

  // gives leading 1 in input, with LSB 1 returning index 0 and MSB 1 returning index 63
  leading_one_calc #(
    .DEBUG (DEBUG),
    .N (64),
    .N_BITS (6)
  ) leading_one_calc_inst (
    .loc_din (in_unsigned),
    .loc_dout (in_unsigned_loc)
  );

  // Normalize: shift so the leading 1 (hidden bit) sits at bit 63.
  // 63 - loc fits in 6 bits for loc in [0, 63].
  assign norm_shift_amount = 6'd63 - in_unsigned_loc;
  assign in_normalized     = in_unsigned << norm_shift_amount;

  // Fixed bit positions after normalization:
  //   [63]    hidden bit (dropped)
  //   [62:11] 52-bit mantissa
  //   [10]    guard
  //   [9]     round
  //   [8:0]   sticky (OR-reduced)
  // For loc <= 52 the bits below the mantissa are all zero, so no rounding
  // happens and this single path covers both of the old cases.
  assign mant_truncated = in_normalized[62:11];
  assign guard_bit      = in_normalized[10];
  assign round_bit      = in_normalized[9];
  assign sticky_bit     = |in_normalized[8:0];

  // Round to nearest, ties to even:
  //   G=0           -> below halfway, truncate
  //   G=1, R|S=1    -> above halfway, round up
  //   G=1, R|S=0    -> exact tie, round up only if mantissa LSB is 1
  assign round_up = guard_bit & (round_bit | sticky_bit | mant_truncated[0]);

  assign mant_rounded   = {1'b0, mant_truncated} + {52'd0, round_up};
  assign mant_round_ovf = mant_rounded[52];

  // On overflow (mantissa was all ones), the significand becomes 10.000...0,
  // i.e. mantissa 0 with exponent + 1. mant_rounded[51:0] is already 0 then.
  assign out_mant = mant_rounded[51:0];

  // Biased exponent = loc + 1023 (+1 if rounding overflowed).
  // Max: 63 + 1023 + 1 = 1087, well inside 11 bits, so no overflow to Inf.
  assign out_exp = 11'd1023 + {5'd0, in_unsigned_loc} + {10'd0, mant_round_ovf};

  always@ (posedge clk) begin
    if (~rst_n) begin
      int2fpr_out_tvalid_reg <= 0;
      int2fpr_out_tdata_reg <= 0;
    end else begin
      int2fpr_out_tvalid_reg <= int2fpr_in_tvalid;
      if (in_tdata_is_0) begin
        int2fpr_out_tdata_reg <= 64'h0;
      end else begin
        int2fpr_out_tdata_reg <= {out_sign, out_exp, out_mant};
      end
    end
  end

  assign int2fpr_out_tvalid = int2fpr_out_tvalid_reg;
  assign int2fpr_out_tdata = int2fpr_out_tdata_reg;
endmodule
