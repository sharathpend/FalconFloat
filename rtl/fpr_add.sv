
`include "defines.vh"

// IEEE-754 binary64 adder, round-to-nearest-even.
// Scope (matches FALCON's needs): inputs are zero or normal numbers, results are
// zero or normal. Inf, NaN, subnormals and exponent overflow/underflow are not
// handled; an exponent of 0 on an input is treated as zero.
module fpr_add #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_add_in_tvalid,
  input  wire [63:0]  fpr_add_in1_tdata,
  input  wire [63:0]  fpr_add_in2_tdata,

  output wire         fpr_add_out_tvalid,
  output wire [63:0]  fpr_add_out_tdata
);

  wire        in1_sign, in2_sign;
  wire [10:0] in1_exp,  in2_exp;
  wire [51:0] in1_mant, in2_mant;
  wire        in1_is_zero, in2_is_zero; // exp == 0

  wire        swap;                     // 1 when |in2| > |in1|
  wire        big_sign,    small_sign;
  wire [10:0] big_exp,     small_exp;
  wire [51:0] big_mant,    small_mant;
  wire        big_is_zero, small_is_zero;

  wire        eff_sub;                  // signs differ -> effective subtraction
  wire [10:0] exp_diff;                 // big_exp - small_exp, always >= 0

  // Significands with 3 extra low bits: {hidden, mant[51:0], G, R, S}
  wire [55:0] big_sig;
  wire [55:0] small_sig;
  wire [55:0] small_sig_shifted;
  wire [55:0] shifted_out_mask;
  wire        sticky;
  wire [55:0] small_sig_aligned;        // shifted, with sticky ORed into bit 0

  wire [56:0] sum;                      // bit 56 = carry out of an effective add
  wire        both_zero;
  wire [63:0] out_tdata;

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         fpr_add_out_tvalid_reg = 'd0;
    (* dont_touch = "true" *) reg  [63:0] fpr_add_out_tdata_reg = 'd0;
  `else
    (* dont_touch = "true" *) reg         fpr_add_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_add_out_tdata_reg;
  `endif

  // ---------------------------------------------------------------------------
  // Unpack
  // ---------------------------------------------------------------------------
  assign in1_sign = fpr_add_in1_tdata[63];
  assign in1_exp  = fpr_add_in1_tdata[62:52];
  assign in1_mant = fpr_add_in1_tdata[51:0];
  assign in2_sign = fpr_add_in2_tdata[63];
  assign in2_exp  = fpr_add_in2_tdata[62:52];
  assign in2_mant = fpr_add_in2_tdata[51:0];

  assign in1_is_zero = (in1_exp == 11'd0);
  assign in2_is_zero = (in2_exp == 11'd0);

  // ---------------------------------------------------------------------------
  // Order operands by magnitude, so the subtraction below never goes negative
  // and the result sign is simply the sign of the larger operand.
  // {exp, mant} compares magnitudes directly for normal numbers.
  // ---------------------------------------------------------------------------
  assign swap = {in2_exp, in2_mant} > {in1_exp, in1_mant};

  assign big_sign      = swap ? in2_sign    : in1_sign;
  assign big_exp       = swap ? in2_exp     : in1_exp;
  assign big_mant      = swap ? in2_mant    : in1_mant;
  assign big_is_zero   = swap ? in2_is_zero : in1_is_zero;
  assign small_sign    = swap ? in1_sign    : in2_sign;
  assign small_exp     = swap ? in1_exp     : in2_exp;
  assign small_mant    = swap ? in1_mant    : in2_mant;
  assign small_is_zero = swap ? in1_is_zero : in2_is_zero;

  assign eff_sub  = big_sign ^ small_sign;
  assign exp_diff = big_exp - small_exp;

  assign big_sig   = big_is_zero   ? 56'd0 : {1'b1, big_mant,   3'b000};
  assign small_sig = small_is_zero ? 56'd0 : {1'b1, small_mant, 3'b000};

  // ---------------------------------------------------------------------------
  // Alignment with a real sticky bit.
  // Every bit shifted out past S is ORed together into S. Without this, a tiny
  // operand that is shifted away entirely looks like an exact zero, and both
  // rounding and subtraction borrows come out wrong.
  // ---------------------------------------------------------------------------
  assign small_sig_shifted = (exp_diff >= 11'd56) ? 56'd0 : (small_sig >> exp_diff[5:0]);
  assign shifted_out_mask  = (exp_diff >= 11'd56) ? {56{1'b1}} : ~({56{1'b1}} << exp_diff[5:0]);
  assign sticky            = |(small_sig & shifted_out_mask);
  assign small_sig_aligned = {small_sig_shifted[55:1], small_sig_shifted[0] | sticky};

  // big_sig >= small_sig_aligned always holds, so this never underflows.
  assign sum = eff_sub ? ({1'b0, big_sig} - {1'b0, small_sig_aligned})
                       : ({1'b0, big_sig} + {1'b0, small_sig_aligned});

  assign both_zero = in1_is_zero & in2_is_zero;

  // Normalize, round (RNE), pack.
  fpr_add_norm #(
    .DEBUG (DEBUG)
  ) fpr_add_norm_inst (
    .sum         (sum),
    .big_exp     (big_exp),
    .result_sign (big_sign),
    .zero_sign   (both_zero ? (in1_sign & in2_sign) : 1'b0), // -0 + -0 = -0, x + (-x) = +0
    .result      (out_tdata)
  );

  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_add_out_tvalid_reg <= 0;
      fpr_add_out_tdata_reg <= 0;
    end else begin
      fpr_add_out_tvalid_reg <= fpr_add_in_tvalid;
      fpr_add_out_tdata_reg  <= out_tdata;
    end
  end

  assign fpr_add_out_tvalid = fpr_add_out_tvalid_reg;
  assign fpr_add_out_tdata  = fpr_add_out_tdata_reg;

endmodule
