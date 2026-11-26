
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`include "defines.vh"

// floor(x) as a signed int64 and as a double, and the residue r = x - floor(x).
// Matches FALCON's  s = fpr_floor(x);  f = fpr_of(s);  r = fpr_sub(x, f).
// The int64 floor and residue come from fpr_floor_and_residue. The double floor
// is built directly from x by clearing the fraction bits, plus one integer ulp
// for a negative x with a fraction (exact, may carry into the exponent).
// For |x| >= 2^63 the double floor is x itself (the int64 floor saturates).
module fpr_floor_int_fpr_and_residue #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_floor_int_fpr_and_residue_in_tvalid,
  input  wire [63:0]  fpr_floor_int_fpr_and_residue_in_tdata,

  output wire         fpr_floor_int_fpr_and_residue_out_tvalid,
  output wire [63:0]  fpr_floor_int_fpr_and_residue_out_floor_int, // signed int64
  output wire [63:0]  fpr_floor_int_fpr_and_residue_out_floor_fpr, // double
  output wire [63:0]  fpr_floor_int_fpr_and_residue_out_residue    // double in [0, 1]
);

  wire         in1_sign;
  wire [10:0]  in1_exp;
  wire [51:0]  in1_mant;
  wire         in1_is_zero;       // exp == 0
  wire         in1_lt_one;        // |x| < 1
  wire         in1_is_int;        // |x| >= 2^52, no fraction bits

  wire [10:0]  frac_shift_full;
  wire [5:0]   frac_shift;        // exp - 1023, valid range 0..51
  wire [51:0]  frac_mask;         // 1s on the fraction bits of the mantissa
  wire [51:0]  mant_int_bits;
  wire         frac_is_nonzero;
  wire [52:0]  int_ulp;           // weight 2^0 in {1.mant}
  wire [53:0]  mag_plus_one;      // {1.mant_int_bits} + 1, bit 53 = carry
  wire [10:0]  mag_plus_one_exp;

  wire [63:0]  out_floor_fpr;

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg  [63:0] fpr_floor_int_fpr_and_residue_out_floor_fpr_reg = 0;
  `else
    (* dont_touch = "true" *) reg  [63:0] fpr_floor_int_fpr_and_residue_out_floor_fpr_reg;
  `endif

  fpr_floor_and_residue #(
    .DEBUG (DEBUG)
  ) fpr_floor_and_residue_inst (
    .clk                               (clk),
    .rst_n                             (rst_n),

    .fpr_floor_and_residue_in_tvalid   (fpr_floor_int_fpr_and_residue_in_tvalid),
    .fpr_floor_and_residue_in_tdata    (fpr_floor_int_fpr_and_residue_in_tdata),

    .fpr_floor_and_residue_out_tvalid  (fpr_floor_int_fpr_and_residue_out_tvalid),
    .fpr_floor_and_residue_out_floor   (fpr_floor_int_fpr_and_residue_out_floor_int),
    .fpr_floor_and_residue_out_residue (fpr_floor_int_fpr_and_residue_out_residue)
  );

  assign in1_sign = fpr_floor_int_fpr_and_residue_in_tdata[63];
  assign in1_exp  = fpr_floor_int_fpr_and_residue_in_tdata[62:52];
  assign in1_mant = fpr_floor_int_fpr_and_residue_in_tdata[51:0];

  assign in1_is_zero = (in1_exp == 11'd0);
  assign in1_lt_one  = (in1_exp < 11'd1023);
  assign in1_is_int  = (in1_exp >= 11'd1075);

  assign frac_shift_full  = in1_exp - 11'd1023;
  assign frac_shift       = frac_shift_full[5:0];
  assign frac_mask        = {52{1'b1}} >> frac_shift;
  assign mant_int_bits    = in1_mant & ~frac_mask;
  assign frac_is_nonzero  = |(in1_mant & frac_mask);
  assign int_ulp          = {frac_mask, 1'b1} & ~{1'b0, frac_mask};
  assign mag_plus_one     = {2'b01, mant_int_bits} + {1'b0, int_ulp};
  assign mag_plus_one_exp = in1_exp + {10'd0, mag_plus_one[53]};

  assign out_floor_fpr = in1_is_zero                     ? 64'd0 :
                         in1_lt_one                      ? (in1_sign ? 64'hBFF0_0000_0000_0000 : 64'd0) : // -1.0 or +0
                         (in1_is_int | ~frac_is_nonzero) ? fpr_floor_int_fpr_and_residue_in_tdata :
                         in1_sign                        ? {1'b1, mag_plus_one_exp, mag_plus_one[51:0]} :
                                                           {1'b0, in1_exp, mant_int_bits};

  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_floor_int_fpr_and_residue_out_floor_fpr_reg <= 64'd0;
    end else begin
      fpr_floor_int_fpr_and_residue_out_floor_fpr_reg <= out_floor_fpr;
    end
  end

  assign fpr_floor_int_fpr_and_residue_out_floor_fpr = fpr_floor_int_fpr_and_residue_out_floor_fpr_reg;

endmodule
