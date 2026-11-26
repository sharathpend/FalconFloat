
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

// Double to signed int64, rounded toward zero (FALCON fpr_trunc).
// Inputs with |x| >= 2^63 saturate to 0x7FFF_FFFF_FFFF_FFFF / 0x8000_0000_0000_0000
// (-2^63 itself is exact).
`include "defines.vh"

module fpr_trunc #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_trunc_in_tvalid,
  input  wire [63:0]  fpr_trunc_in_tdata,

  output wire         fpr_trunc_out_tvalid,
  output wire [63:0]  fpr_trunc_out_tdata
);

  wire         in1_sign;
  wire [10:0]  in1_exp;
  wire [51:0]  in1_mant;
  wire [52:0]  in1_mant_extended;
  wire         in1_lt_one;              // |x| < 1 (includes zero) -> 0
  wire         in1_out_of_int64_bounds; // |x| >= 2^63 -> saturate

  wire [10:0]  decomp_shift_full;
  wire [5:0]   decomp_shift;            // exp - 1022, valid range 0..63
  wire [116:0] decomp_fixed;            // fixed point: [116:53] integer, [52:0] fraction
  wire [63:0]  int_part;
  wire [52:0]  frac_part;               // unused, the fraction is dropped

  wire [63:0]  out_int;

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         fpr_trunc_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_trunc_out_tdata_reg = 0;
  `else
    (* dont_touch = "true" *) reg         fpr_trunc_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_trunc_out_tdata_reg;
  `endif

  assign in1_sign          = fpr_trunc_in_tdata[63];
  assign in1_exp           = fpr_trunc_in_tdata[62:52];
  assign in1_mant          = fpr_trunc_in_tdata[51:0];
  assign in1_mant_extended = {1'b1, in1_mant};

  assign in1_lt_one              = (in1_exp < 11'd1023);
  assign in1_out_of_int64_bounds = (in1_exp >= 11'd1086);

  assign decomp_shift_full = in1_exp - 11'd1022;
  assign decomp_shift      = decomp_shift_full[5:0];
  assign decomp_fixed      = {64'd0, in1_mant_extended} << decomp_shift;
  assign int_part          = decomp_fixed[116:53];
  assign frac_part         = decomp_fixed[52:0];

  assign out_int = in1_lt_one              ? 64'd0 :
                   in1_out_of_int64_bounds ? (in1_sign ? 64'h8000_0000_0000_0000 : 64'h7FFF_FFFF_FFFF_FFFF) :
                   in1_sign                ? ((~int_part) + 64'd1) :
                                             int_part;

  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_trunc_out_tvalid_reg <= 1'b0;
      fpr_trunc_out_tdata_reg  <= 64'd0;
    end else begin
      fpr_trunc_out_tvalid_reg <= fpr_trunc_in_tvalid;
      fpr_trunc_out_tdata_reg  <= out_int;
    end
  end

  assign fpr_trunc_out_tvalid = fpr_trunc_out_tvalid_reg;
  assign fpr_trunc_out_tdata  = fpr_trunc_out_tdata_reg;

endmodule
