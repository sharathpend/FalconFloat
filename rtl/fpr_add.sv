
`include "defines.vh"

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


  wire        in1_sign;
  wire [10:0] in1_exp;
  wire [51:0] in1_mant;
  wire [52:0] in1_mant_extended;
  wire        in1_is_zero;

  wire        in2_sign;
  wire [10:0] in2_exp;
  wire [51:0] in2_mant;
  wire [52:0] in2_mant_extended;
  wire        in2_is_zero;

  wire output_result_zero;

  wire        out_sign;
  wire [10:0] out_exp;
  wire [51:0] out_mant;

  wire [10:0] exp_in1_sub_in2;
  wire [10:0] exp_in2_sub_in1;
  wire [10:0] result_exp;
  wire [52:0] in1_mant_shifted;
  wire [52:0] in2_mant_shifted;

  wire shifted_mantissa_g;
  wire shifted_mantissa_r;
  wire shifted_mantissa_s;

  wire [53:0] result_mant_in1_add_in2;
  wire [53:0] result_mant_in1_sub_in2;
  wire [53:0] result_mant_in2_sub_in1;
  wire        result_sign;
  wire [53:0] result_mant_add;
  wire [53:0] result_mant_sub;


  wire final_sign;
  wire [10:0] final_exp;
  wire [52:0] final_mant;
  

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         fpr_add_out_tvalid_reg = 'd0;
    (* dont_touch = "true" *) reg  [63:0] fpr_add_out_tdata_reg = 'd0;
  `else
    (* dont_touch = "true" *) reg         fpr_add_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_add_out_tdata_reg;
  `endif


  assign in1_sign = fpr_add_in1_tdata[63];
  assign in1_exp  = fpr_add_in1_tdata[(63-1)-:11];
  assign in1_mant = fpr_add_in1_tdata[(63-1-11):0];
  assign in1_mant_extended = {1'b1, in1_mant};
  assign in1_is_zero = ((in1_exp == 'd0) && (in1_mant == 'd0)) ? 1'b1 : 1'b0;

  assign in2_sign = fpr_add_in2_tdata[63];
  assign in2_exp  = fpr_add_in2_tdata[(63-1)-:11];
  assign in2_mant = fpr_add_in2_tdata[(63-1-11):0];
  assign in2_mant_extended = {1'b1, in2_mant};
  assign in2_is_zero = ((in2_exp == 'd0) && (in2_mant == 'd0)) ? 1'b1 : 1'b0;

  assign output_result_zero = ((in1_exp == in2_exp) && (in1_mant == in2_mant) && (in1_sign != in2_sign)) ? 1'b1 : 1'b0;
  
  
  // Adjusting the mantissa so the explonent values are the same for addition
  assign exp_in1_sub_in2 = in1_exp - in2_exp;
  assign exp_in2_sub_in1 = in2_exp - in1_exp;

  // I'm not doing correct GRS here. This is an issue. Not sure how to do dynamic part of S. I am taking only 1 bit here,
  // instead of performing an OR on all remaining sticky bits.
  assign in1_mant_shifted = (in2_exp > in1_exp) ? (in1_mant_extended>>exp_in2_sub_in1) : in1_mant_extended;
  assign in2_mant_shifted = (in1_exp > in2_exp) ? (in2_mant_extended>>exp_in1_sub_in2) : in2_mant_extended;
  assign result_exp = (in2_exp > in1_exp) ? in2_exp : in1_exp;
  assign shifted_mantissa_g = (in2_exp > in1_exp) ? in1_mant_extended[exp_in2_sub_in1-1] : 
                              (in1_exp > in2_exp) ? in2_mant_extended[exp_in1_sub_in2-1] : 1'b0;
  assign shifted_mantissa_r = (in2_exp > in1_exp) && (exp_in2_sub_in1 > 'd1) ? in1_mant_extended[exp_in2_sub_in1-2] : 
                              (in1_exp > in2_exp) && (exp_in1_sub_in2 > 'd1) ? in2_mant_extended[exp_in1_sub_in2-2] : 1'b0;
  assign shifted_mantissa_s = (in2_exp > in1_exp) && (exp_in2_sub_in1 > 'd2) ? in1_mant_extended[exp_in2_sub_in1-3] : 
                              (in1_exp > in2_exp) && (exp_in1_sub_in2 > 'd2) ? in2_mant_extended[exp_in1_sub_in2-3] : 1'b0;


  assign result_mant_in1_add_in2 = {1'b0, in1_mant_shifted} + {1'b0, in2_mant_shifted};
  assign result_mant_in1_sub_in2 = {1'b0, in1_mant_shifted} - {1'b0, in2_mant_shifted};
  assign result_mant_in2_sub_in1 = {1'b0, in2_mant_shifted} - {1'b0, in1_mant_shifted};
  assign result_sign = (in2_mant_shifted > in1_mant_shifted) ? in2_sign : in1_sign;
  assign result_mant_add = result_mant_in1_add_in2;
  assign result_mant_sub = (in2_mant_shifted > in1_mant_shifted) ? result_mant_in2_sub_in1 : result_mant_in1_sub_in2;
  
  fpr_add_norm fpr_add_norm_inst (
    .in1_sign (in1_sign),
    .in2_sign (in2_sign),
    .result_mant_add (result_mant_add),
    .result_mant_sub (result_mant_sub),
    .result_exp (result_exp),

    .shifted_mantissa_g (shifted_mantissa_g),
    .shifted_mantissa_r (shifted_mantissa_r),
    .shifted_mantissa_s (shifted_mantissa_s),
    
    .final_mant (final_mant),
    .final_exp (final_exp)
  );

  assign final_sign = result_sign;

  assign out_sign = (in1_is_zero == 1'b1) ? in2_sign : 
                    (in2_is_zero == 1'b1) ? in1_sign : final_sign;

  assign out_exp  = (in1_is_zero == 1'b1) ? in2_exp : 
                    (in2_is_zero == 1'b1) ? in1_exp : final_exp;

  assign out_mant = (in1_is_zero == 1'b1) ? in2_mant : 
                    (in2_is_zero == 1'b1) ? in1_mant : final_mant[51:0];

  // Output
  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_add_out_tvalid_reg <= 0;
      fpr_add_out_tdata_reg <= 0;
    end else begin
      fpr_add_out_tvalid_reg <= fpr_add_in_tvalid;
      if (output_result_zero)
        fpr_add_out_tdata_reg <= 0;
      else
        fpr_add_out_tdata_reg  <= {out_sign, out_exp, out_mant};
    end
  end

  assign fpr_add_out_tvalid = fpr_add_out_tvalid_reg;
  assign fpr_add_out_tdata  = fpr_add_out_tdata_reg;

endmodule