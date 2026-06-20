
`include "defines.vh"

module fpr_floor #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_floor_in_tvalid,
  input  wire [63:0]  fpr_floor_in_tdata,

  output wire         fpr_floor_out_tvalid,
  output wire [63:0]  fpr_floor_out_tdata
);

  wire        in1_sign;
  wire [10:0] in1_exp;
  wire [10:0] in1_exp_adjusted; // adjust for 1023 bias
  wire        in1_exp_adjusted_lt_0; // is adjusted exp < 0
  wire        in1_exp_adjusted_gt_51; // is adjusted exp > 51
  wire [51:0] in1_mant;
  wire [52:0] in1_mant_extended;
  wire [62:0] in1_mant_extended_63b_size; // 63b size of mantissa, to shift for signed 64b int
  wire [62:0] in1_mant_extended_63b_size_shifted;
  wire [63:0] in1_mant_extended_64b_size; // in1_mant_extended_63b_size_shifted + sign bit (0), then converted according to input sign bit
  wire        in1_is_zero; // is input 0
  wire        in1_out_of_int64_bounds; // if exp > 63, then it is out of bounds of signed 64b int.

  wire [10:0] mant_shift_1; // used when in1_exp_adjusted >= 52
  wire [10:0] mant_shift_2; // used when in1_exp_adjusted < 52
  wire [62:0] mant_int_part_without_sign;
  wire [63:0] mant_int_part_positive_sign_extended;
  wire [51:0] mant_frac_part;
  wire        mant_has_frac_part;

  // full size frac mask, will be shifted based on exp.
  // after shift, integer part of mask will be 0, frac will be 1. Can be ANDED with mantisa without the implied 1.
  reg  [51:0] frac_mask = {52{1'b1}};
  wire [51:0] mant_frac_mask;

  
  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         fpr_floor_out_tvalid_reg = 'd0;
    (* dont_touch = "true" *) reg  [63:0] fpr_floor_out_tdata_reg = 'd0;
  `else
    (* dont_touch = "true" *) reg         fpr_floor_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_floor_out_tdata_reg;
  `endif


  assign in1_sign = fpr_floor_in_tdata[63];
  assign in1_exp  = fpr_floor_in_tdata[(63-1)-:11]; // 62:52
  assign in1_mant = fpr_floor_in_tdata[(63-1-11):0]; // 51:0

  assign in1_exp_adjusted  = in1_exp - 10'd1023;
  assign in1_exp_adjusted_lt_0 = (in1_exp < 11'd1023) ? 1'b1 : 1'b0; // in1_exp - 11'd1023 < 0
  assign in1_exp_adjusted_gt_51 = (in1_exp > 11'd1074) ? 1'b1 : 1'b0; // in1_exp - 11'd1023 > 51
  assign in1_mant_extended = {1'b1, in1_mant};
  assign in1_mant_extended_63b_size = {10'b0, in1_mant_extended};
  assign in1_is_zero = ((in1_exp == 'd0) && (in1_mant == 'd0)) ? 1'b1 : 1'b0;
  assign in1_out_of_int64_bounds = (in1_exp >= 11'd1086) ? 1'b1 : 1'b0; // in1_exp - 11'd1023 >= 63

  // if in1_exp_adjusted is positive and >= 52, it has only integer part, no frac part in mantissa.
  assign mant_shift_1 = in1_exp - 11'd1075; // in1_exp_adjusted - 11'd52
  assign in1_mant_extended_63b_size_shifted = in1_mant_extended_63b_size << mant_shift_1;
  assign in1_mant_extended_64b_size = {1'b0, in1_mant_extended_63b_size_shifted};

  // if in1_exp_adjusted is positive and < 52, then the mantissa has a frac part.
  assign mant_shift_2 = 11'd1075 - in1_exp; // 11'd52 - in1_exp_adjusted (would it be better to take 2's compl of mant_shift_1?)
  assign mant_int_part_without_sign = in1_mant_extended_63b_size >> mant_shift_2;
  assign mant_int_part_positive_sign_extended = {1'b0, mant_int_part_without_sign};
  assign mant_frac_mask = frac_mask >> in1_exp_adjusted;
  assign mant_frac_part = in1_mant & mant_frac_mask;
  assign mant_has_frac_part = (mant_frac_part == 52'b0) ? 1'b0 : 1'b1;
  
  
  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_floor_out_tvalid_reg <= 1'b0;
      fpr_floor_out_tdata_reg <= 64'b0;
    end else begin
      fpr_floor_out_tvalid_reg <= fpr_floor_in_tvalid;

      if (DEBUG) begin
        if (fpr_floor_out_tvalid_reg) $display("Input");
        if (fpr_floor_out_tvalid_reg) $display("in1_sign                =   %b"  , in1_sign);
        if (fpr_floor_out_tvalid_reg) $display("in1_exp                 = 0x%h"  , in1_exp);
        if (fpr_floor_out_tvalid_reg) $display("in1_mant                = 0x%h\n", in1_mant);
        if (fpr_floor_out_tvalid_reg) $display("Input extensions");
        if (fpr_floor_out_tvalid_reg) $display("in1_exp_adjusted        = 0x%h"  , in1_exp_adjusted);
        if (fpr_floor_out_tvalid_reg) $display("in1_exp_adjusted_lt_0   =   %b"  , in1_exp_adjusted_lt_0);
        if (fpr_floor_out_tvalid_reg) $display("in1_exp_adjusted_gt_51  =   %b"  , in1_exp_adjusted_gt_51);
        if (fpr_floor_out_tvalid_reg) $display("in1_mant_extended       = 0x%h"  , in1_mant_extended);
        if (fpr_floor_out_tvalid_reg) $display("in1_is_zero             =   %b"  , in1_is_zero);
        if (fpr_floor_out_tvalid_reg) $display("in1_out_of_int64_bounds =   %b\n", in1_out_of_int64_bounds);
      end
      if (in1_is_zero) begin // input  = 0
        fpr_floor_out_tdata_reg <= 0;
        if (DEBUG) begin
          if (fpr_floor_out_tvalid_reg) $display("Input = 0");
        end
      end else if (in1_exp_adjusted_lt_0) begin // very small number
        if (DEBUG) begin
          if (fpr_floor_out_tvalid_reg) $display("Input = small number (in1_exp_adjusted_lt_0 = %b)", in1_exp_adjusted_lt_0);
        end
        if (in1_sign) begin // negative
          if (DEBUG) begin
            if (fpr_floor_out_tvalid_reg) $display("Input is negative");
          end
          fpr_floor_out_tdata_reg <= 64'hFFFF_FFFF_FFFF_FFFF; // -1 in signed int64
        end else begin // positive
          if (DEBUG) begin
            if (fpr_floor_out_tvalid_reg) $display("Input is positive");
          end
          fpr_floor_out_tdata_reg <= 64'h0;
        end
      end else if (in1_out_of_int64_bounds) begin // out of bounds
        if (DEBUG) begin
          if (fpr_floor_out_tvalid_reg) $display("Input = out of int64 bounds (in1_out_of_int64_bounds = %b)", in1_out_of_int64_bounds);
        end
        if (in1_sign) begin // negative
          if (DEBUG) begin
            if (fpr_floor_out_tvalid_reg) $display("Input is negative");
          end
          fpr_floor_out_tdata_reg <= 64'h8000_0000_0000_0000; // smallest negative number
        end else begin // positive
          if (DEBUG) begin
            if (fpr_floor_out_tvalid_reg) $display("Input is positive");
          end
          fpr_floor_out_tdata_reg <= 64'h7FFF_FFFF_FFFF_FFFF; // largest positive number
        end
      end else if (in1_exp_adjusted_gt_51) begin // exp > 51 (or the same as exp >= 52)
        if (DEBUG) begin
          if (fpr_floor_out_tvalid_reg) $display("Mantissa has no fract value (in1_exp_adjusted_gt_51 = %b) (expected 1)", in1_exp_adjusted_gt_51);
        end
        if (in1_sign) begin // negative, take 2's compl
          if (DEBUG) begin
            if (fpr_floor_out_tvalid_reg) $display("Input is negative");
          end
          fpr_floor_out_tdata_reg <= (~in1_mant_extended_64b_size) + 1'b1;
        end else begin // positive
          if (DEBUG) begin
            if (fpr_floor_out_tvalid_reg) $display("Input is positive");
          end
          fpr_floor_out_tdata_reg <= in1_mant_extended_64b_size;
        end
      end else begin // exp < 52
        if (DEBUG) begin
          if (fpr_floor_out_tvalid_reg) $display("Mantissa has a fract value (in1_exp_adjusted_gt_51 = %b) (expected 0)", in1_exp_adjusted_gt_51);
        end
        if (in1_sign) begin // negative
          if (DEBUG) begin
            if (fpr_floor_out_tvalid_reg) $display("Input is negative");
          end
          if (mant_has_frac_part) begin// mantissa has a fractional part
            fpr_floor_out_tdata_reg <= ~mant_int_part_positive_sign_extended; // 2's compl - 1'b1 = negate the positive number
          end else begin// mantissa has no fractional part
            fpr_floor_out_tdata_reg <= (~mant_int_part_positive_sign_extended) + 1'b1; // regular 2's compl
          end
        end else begin // positive
          if (DEBUG) begin
            if (fpr_floor_out_tvalid_reg) $display("Input is positive");
          end
          fpr_floor_out_tdata_reg <= mant_int_part_positive_sign_extended;
        end
        if (DEBUG) begin
          if (fpr_floor_out_tvalid_reg) $display("mant_shift_2               =   %d", mant_shift_2);
          if (fpr_floor_out_tvalid_reg) $display("mant_int_part_without_sign = 0x%h", mant_int_part_without_sign);
          if (fpr_floor_out_tvalid_reg) $display("mant_frac_mask             = 0x%h", mant_frac_mask);
          if (fpr_floor_out_tvalid_reg) $display("mant_frac_part             = 0x%h", mant_frac_part);
          if (fpr_floor_out_tvalid_reg) $display("mant_has_frac_part         =   %b", mant_has_frac_part);
        end
      end
    end
  end

  assign fpr_floor_out_tvalid = fpr_floor_out_tvalid_reg;
  assign fpr_floor_out_tdata  = fpr_floor_out_tdata_reg;

endmodule
