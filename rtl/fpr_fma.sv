
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`include "defines.vh"

// Multiply-add: out = (+/-)(a * b) + (+/-)c, round to nearest even.
//   op[1] = 1 negates a * b, op[0] = 1 negates c.
//
// FUSED = 1: single rounding of the exact a * b + c (IEEE fusedMultiplyAdd).
// FUSED = 0: a * b is rounded first, so the result is bit-exact with
//            fpr_add(fpr_mul(a, b), c), as in FALCON's reference code.
// REG_STAGES = 1: 1-cycle latency.
// REG_STAGES = 2: 2-cycle latency, extra register after the multiplier.
// INTERNAL_MULT = 0: the 53x53 product comes from a shared multiplier through the
//                    uint64_mult_* ports (see fpr_fma_top).
// INTERNAL_MULT = 1: standalone, the product is computed inside (uint_mul_core,
//                    N = 53). uint64_mult_result is ignored and can be tied to 0.
//
// Both operands are put in a 106-bit significand with the leading 1 at bit 105
// (the product exactly, c padded with zeros), then added like fpr_add with
// G/R/S bits and one normalize + round. Exponents are kept with a +2048 offset
// in 13 bits, so a product outside the double range is still handled when c
// brings the result back into range (FUSED = 1).
//
// Scope (matches FALCON's needs): inputs are zero or normal, the result is zero or
// normal. With FUSED = 0 the rounded product must also be zero or normal.
// An exponent of 0 on an input is treated as zero. Output data only updates on a
// valid input.
module fpr_fma #(
  parameter DEBUG         = 0,
  parameter FUSED         = 1,
  parameter REG_STAGES    = 1,
  parameter INTERNAL_MULT = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_fma_in_tvalid,
  input  wire [63:0]  fpr_fma_in1_tdata, // a
  input  wire [63:0]  fpr_fma_in2_tdata, // b
  input  wire [63:0]  fpr_fma_in3_tdata, // c
  input  wire [1:0]   fpr_fma_op,        // [1]: negate a * b, [0]: negate c

  // to-from shared multiplier
  output wire [63:0]  uint64_mult_in1,
  output wire [63:0]  uint64_mult_in2,
  input  wire [127:0] uint64_mult_result,

  output wire         fpr_fma_out_tvalid,
  output wire [63:0]  fpr_fma_out_tdata
);

  // ---------------------------------------------------------------------------
  // Stage A: unpack and multiply
  // ---------------------------------------------------------------------------
  wire         a_sign, b_sign, c_sign;
  wire [10:0]  a_exp,  b_exp,  c_exp;
  wire [51:0]  a_mant, b_mant, c_mant;
  wire [52:0]  a_mant_extended, b_mant_extended;
  wire         a_is_zero, b_is_zero;

  wire [105:0] prod_raw;              // {1.a} * {1.b}, in [2^104, 2^106)
  wire         prod_raw_msb;
  wire [12:0]  prod_exp_base;         // a_exp + b_exp - 1023, +2048 offset

  wire [105:0] prod_sig_fused;
  wire [12:0]  prod_exp_fused;

  wire [51:0]  prod_mant_truncated;   // FUSED = 0: product rounded like fpr_mul
  wire         prod_lsb_bit;
  wire         prod_guard_bit;
  wire         prod_sticky_bit;
  wire         prod_round_up;
  wire [53:0]  prod_mant_rounded;     // bit 53 = carry out of rounding
  wire [105:0] prod_sig_unfused;
  wire [12:0]  prod_exp_unfused;

  // Stage A outputs (_d), registered when REG_STAGES = 2
  wire [105:0] sa_prod_sig_d;
  wire [12:0]  sa_prod_exp_d;
  wire         sa_prod_sign_d;
  wire         sa_prod_is_zero_d;
  wire         sa_c_sign_d;

  wire         sa_valid;
  wire [105:0] sa_prod_sig;           // leading 1 at bit 105 (0 if a * b = 0)
  wire [12:0]  sa_prod_exp;           // biased exponent of sa_prod_sig, +2048 offset
  wire         sa_prod_sign;
  wire         sa_prod_is_zero;
  wire         sa_c_sign;             // after op[0]
  wire [10:0]  sa_c_exp;
  wire [51:0]  sa_c_mant;
  wire         sa_c_is_zero;

  assign a_sign = fpr_fma_in1_tdata[63];
  assign a_exp  = fpr_fma_in1_tdata[62:52];
  assign a_mant = fpr_fma_in1_tdata[51:0];
  assign b_sign = fpr_fma_in2_tdata[63];
  assign b_exp  = fpr_fma_in2_tdata[62:52];
  assign b_mant = fpr_fma_in2_tdata[51:0];
  assign c_sign = fpr_fma_in3_tdata[63];
  assign c_exp  = fpr_fma_in3_tdata[62:52];
  assign c_mant = fpr_fma_in3_tdata[51:0];

  assign a_mant_extended = {1'b1, a_mant};
  assign b_mant_extended = {1'b1, b_mant};
  assign a_is_zero       = (a_exp == 11'd0);
  assign b_is_zero       = (b_exp == 11'd0);

  assign uint64_mult_in1 = {11'b0, a_mant_extended};
  assign uint64_mult_in2 = {11'b0, b_mant_extended};

  generate
    if (INTERNAL_MULT) begin : gen_internal_mult
      uint_mul_core #(
        .N (53)
      ) uint_mul_core_inst (
        .a (a_mant_extended),
        .b (b_mant_extended),
        .p (prod_raw)
      );
    end else begin : gen_shared_mult
      assign prod_raw = uint64_mult_result[105:0];
    end
  endgenerate

  assign prod_raw_msb  = prod_raw[105];
  assign prod_exp_base = {2'd0, a_exp} + {2'd0, b_exp} + 13'd1025; // - 1023 + 2048

  // Exact product, normalized to bit 105
  assign prod_sig_fused = prod_raw_msb ? prod_raw : {prod_raw[104:0], 1'b0};
  assign prod_exp_fused = prod_exp_base + {12'd0, prod_raw_msb};

  // Product rounded to 53 bits (same as fpr_mul)
  assign prod_mant_truncated = prod_raw_msb ? prod_raw[104:53] : prod_raw[103:52];
  assign prod_lsb_bit        = prod_mant_truncated[0];
  assign prod_guard_bit      = prod_raw_msb ? prod_raw[52]     : prod_raw[51];
  assign prod_sticky_bit     = prod_raw_msb ? |prod_raw[51:0]  : |prod_raw[50:0];
  assign prod_round_up       = prod_guard_bit & (prod_sticky_bit | prod_lsb_bit);
  assign prod_mant_rounded   = {2'b01, prod_mant_truncated} + {53'd0, prod_round_up};
  assign prod_sig_unfused    = prod_mant_rounded[53] ? {1'b1, 105'd0} : {prod_mant_rounded[52:0], 53'd0};
  assign prod_exp_unfused    = prod_exp_base + {12'd0, prod_raw_msb} + {12'd0, prod_mant_rounded[53]};

  assign sa_prod_is_zero_d = a_is_zero | b_is_zero;
  assign sa_prod_sig_d     = sa_prod_is_zero_d ? 106'd0 : (FUSED ? prod_sig_fused : prod_sig_unfused);
  assign sa_prod_exp_d     = FUSED ? prod_exp_fused : prod_exp_unfused;
  assign sa_prod_sign_d    = a_sign ^ b_sign ^ fpr_fma_op[1];
  assign sa_c_sign_d       = c_sign ^ fpr_fma_op[0];

  generate
    if (REG_STAGES == 2) begin : gen_stage_a_reg
      `ifdef FPGA_DESIGN
        (* dont_touch = "true" *) reg         sa_valid_reg = 0;
        (* dont_touch = "true" *) reg [105:0] sa_prod_sig_reg = 0;
        (* dont_touch = "true" *) reg [12:0]  sa_prod_exp_reg = 0;
        (* dont_touch = "true" *) reg         sa_prod_sign_reg = 0;
        (* dont_touch = "true" *) reg         sa_prod_is_zero_reg = 0;
        (* dont_touch = "true" *) reg [63:0]  sa_c_reg = 0;
      `else
        (* dont_touch = "true" *) reg         sa_valid_reg;
        (* dont_touch = "true" *) reg [105:0] sa_prod_sig_reg;
        (* dont_touch = "true" *) reg [12:0]  sa_prod_exp_reg;
        (* dont_touch = "true" *) reg         sa_prod_sign_reg;
        (* dont_touch = "true" *) reg         sa_prod_is_zero_reg;
        (* dont_touch = "true" *) reg [63:0]  sa_c_reg;
      `endif

      always@ (posedge clk) begin
        if (~rst_n) begin
          sa_valid_reg        <= 1'b0;
          sa_prod_sig_reg     <= 106'd0;
          sa_prod_exp_reg     <= 13'd0;
          sa_prod_sign_reg    <= 1'b0;
          sa_prod_is_zero_reg <= 1'b0;
          sa_c_reg            <= 64'd0;
        end else begin
          sa_valid_reg <= fpr_fma_in_tvalid;
          if (fpr_fma_in_tvalid) begin
            sa_prod_sig_reg     <= sa_prod_sig_d;
            sa_prod_exp_reg     <= sa_prod_exp_d;
            sa_prod_sign_reg    <= sa_prod_sign_d;
            sa_prod_is_zero_reg <= sa_prod_is_zero_d;
            sa_c_reg            <= {sa_c_sign_d, c_exp, c_mant};
          end
        end
      end

      assign sa_valid        = sa_valid_reg;
      assign sa_prod_sig     = sa_prod_sig_reg;
      assign sa_prod_exp     = sa_prod_exp_reg;
      assign sa_prod_sign    = sa_prod_sign_reg;
      assign sa_prod_is_zero = sa_prod_is_zero_reg;
      assign sa_c_sign       = sa_c_reg[63];
      assign sa_c_exp        = sa_c_reg[62:52];
      assign sa_c_mant       = sa_c_reg[51:0];
    end else begin : gen_stage_a_comb
      assign sa_valid        = fpr_fma_in_tvalid;
      assign sa_prod_sig     = sa_prod_sig_d;
      assign sa_prod_exp     = sa_prod_exp_d;
      assign sa_prod_sign    = sa_prod_sign_d;
      assign sa_prod_is_zero = sa_prod_is_zero_d;
      assign sa_c_sign       = sa_c_sign_d;
      assign sa_c_exp        = c_exp;
      assign sa_c_mant       = c_mant;
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Stage B: align, add, normalize, round
  // ---------------------------------------------------------------------------
  wire [105:0] c_sig;
  wire [12:0]  c_exp_off;
  wire         swap;                  // 1 when |c| > |a * b|

  wire         big_sign,  small_sign;
  wire [12:0]  big_exp,   small_exp;
  wire [105:0] big_sig,   small_sig;

  wire         eff_sub;
  wire [12:0]  exp_diff;              // big_exp - small_exp, >= 0 unless small is zero

  // Significands with 3 extra low bits: {sig[105:0], G, R, S}
  wire [108:0] big_ext;
  wire [108:0] small_ext;
  wire [108:0] small_shifted;
  wire [108:0] shifted_out_mask;
  wire         sticky;
  wire [108:0] small_aligned;

  wire [109:0] sum;                   // bit 109 = carry out of an effective add
  wire         sum_is_zero;
  wire         both_zero;

  wire [6:0]   lead_one_loc;
  wire [127:0] sum_norm;              // leading 1 at bit 127
  wire [51:0]  mant_truncated;
  wire         guard_bit;
  wire         sticky_bit;
  wire         round_up;
  wire [52:0]  mant_rounded;          // bit 52 = carry out of rounding
  wire [12:0]  out_exp_full;

  wire [63:0]  out_tdata;

  assign sa_c_is_zero = (sa_c_exp == 11'd0);
  assign c_sig        = sa_c_is_zero ? 106'd0 : {1'b1, sa_c_mant, 53'd0};
  assign c_exp_off    = {2'd0, sa_c_exp} + 13'd2048;

  // Full magnitude compare, a zero operand is always the small one
  assign swap = ~sa_c_is_zero & (sa_prod_is_zero | (c_exp_off > sa_prod_exp) |
                                 ((c_exp_off == sa_prod_exp) & (c_sig > sa_prod_sig)));

  assign big_sign   = swap ? sa_c_sign    : sa_prod_sign;
  assign big_exp    = swap ? c_exp_off    : sa_prod_exp;
  assign big_sig    = swap ? c_sig        : sa_prod_sig;
  assign small_sign = swap ? sa_prod_sign : sa_c_sign;
  assign small_exp  = swap ? sa_prod_exp  : c_exp_off;
  assign small_sig  = swap ? sa_prod_sig  : c_sig;

  assign eff_sub  = big_sign ^ small_sign;
  assign exp_diff = big_exp - small_exp;

  assign big_ext          = {big_sig, 3'b000};
  assign small_ext        = {small_sig, 3'b000};
  assign small_shifted    = (exp_diff >= 13'd109) ? 109'd0 : (small_ext >> exp_diff[6:0]);
  assign shifted_out_mask = (exp_diff >= 13'd109) ? {109{1'b1}} : ~({109{1'b1}} << exp_diff[6:0]);
  assign sticky           = |(small_ext & shifted_out_mask);
  assign small_aligned    = {small_shifted[108:1], small_shifted[0] | sticky};

  assign sum = eff_sub ? ({1'b0, big_ext} - {1'b0, small_aligned}) :
                         ({1'b0, big_ext} + {1'b0, small_aligned});

  assign sum_is_zero = (sum == 110'd0);
  assign both_zero   = sa_prod_is_zero & sa_c_is_zero;

  leading_one_calc #(
    .DEBUG (DEBUG),
    .N (128),
    .N_BITS (7)
  ) leading_one_calc_inst (
    .loc_din  ({sum, 18'd0}),
    .loc_dout (lead_one_loc)
  );

  assign sum_norm       = {sum, 18'd0} << (7'd127 - lead_one_loc);
  assign mant_truncated = sum_norm[126:75];
  assign guard_bit      = sum_norm[74];
  assign sticky_bit     = |sum_norm[73:0];
  assign round_up       = guard_bit & (sticky_bit | mant_truncated[0]);
  assign mant_rounded   = {1'b0, mant_truncated} + {52'd0, round_up};

  // Leading 1 of sum at bit (loc - 18), and bit 108 has the weight of big_exp:
  // exp = big_exp - 2048 + (loc - 18 - 108), +1 if rounding carried out.
  assign out_exp_full = big_exp + {6'd0, lead_one_loc} + {12'd0, mant_rounded[52]} - 13'd2174;

  assign out_tdata = sum_is_zero ? {(both_zero & sa_prod_sign & sa_c_sign), 63'd0} : // -0 + -0 = -0, x + (-x) = +0
                                   {big_sign, out_exp_full[10:0], mant_rounded[51:0]};

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         fpr_fma_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_fma_out_tdata_reg = 0;
  `else
    (* dont_touch = "true" *) reg         fpr_fma_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_fma_out_tdata_reg;
  `endif

  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_fma_out_tvalid_reg <= 1'b0;
      fpr_fma_out_tdata_reg  <= 64'd0;
    end else begin
      fpr_fma_out_tvalid_reg <= sa_valid;
      if (sa_valid) fpr_fma_out_tdata_reg <= out_tdata;
    end
  end

  assign fpr_fma_out_tvalid = fpr_fma_out_tvalid_reg;
  assign fpr_fma_out_tdata  = fpr_fma_out_tdata_reg;

endmodule
