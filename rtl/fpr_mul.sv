
`include "defines.vh"

module fpr_mul #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_mul_in_tvalid,
  input  wire [63:0]  fpr_mul_in1_tdata,
  input  wire [63:0]  fpr_mul_in2_tdata,

  output wire [63:0]  uint64_mult_in1,
  output wire [63:0]  uint64_mult_in2,
  input  wire [127:0] uint64_mult_result,

  output wire         fpr_mul_out_tvalid,
  output wire [63:0]  fpr_mul_out_tdata
);

  `ifdef FPGA_DESIGN
    reg  [15:0] cycle_count = 0; // for debug
  `else
    reg  [15:0] cycle_count; // for debug
  `endif

  wire        in1_sign;
  wire [10:0] in1_exp;
  wire [51:0] in1_mant;
  wire [52:0] in1_mant_extended;

  wire        in2_sign;
  wire [10:0] in2_exp;
  wire [51:0] in2_mant;
  wire [52:0] in2_mant_extended;

  wire        in1_is_zero, in2_is_zero; // exp == 0

  wire        out_sign;
  wire [10:0] out_exp;
  wire [51:0] out_mant;
  wire [63:0] out_tdata;

  wire [105:0] temp_mant;
  wire         temp_mant_msb;
  wire [9:0]   temp_exp_adjust;
  wire [11:0]  temp_exp_extended;
  wire         temp_mant_lsb_bit;
  wire         temp_mant_guard_bit;
  wire         temp_mant_sticky_bit;
  wire         temp_mant_grs;
  wire [51:0]  temp_mant_truncated;
  wire [52:0]  temp_mant_rounded;      // bit 52 = carry out of rounding
  wire         temp_mant_round_ovf;
  wire [10:0]  temp_exp_final;

  
  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         fpr_mul_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_mul_out_tdata_reg = 0;
  `else
    (* dont_touch = "true" *) reg         fpr_mul_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_mul_out_tdata_reg;
  `endif

  
  assign in1_sign = fpr_mul_in1_tdata[63];
  assign in1_exp  = fpr_mul_in1_tdata[(63-1)-:11];
  assign in1_mant = fpr_mul_in1_tdata[(63-1-11):0];
  assign in1_mant_extended = {1'b1, in1_mant};

  assign in2_sign = fpr_mul_in2_tdata[63];
  assign in2_exp  = fpr_mul_in2_tdata[(63-1)-:11];
  assign in2_mant = fpr_mul_in2_tdata[(63-1-11):0];
  assign in2_mant_extended = {1'b1, in2_mant};

  assign in1_is_zero = (in1_exp == 11'd0);
  assign in2_is_zero = (in2_exp == 11'd0);


  // assign temp_mant = in1_mant_extended * in2_mant_extended;
  assign uint64_mult_in1 = {11'b0, in1_mant_extended};
  assign uint64_mult_in2 = {11'b0, in2_mant_extended};
  assign temp_mant = uint64_mult_result[105:0];
  assign temp_mant_msb = temp_mant[105];
  assign temp_exp_adjust = (temp_mant_msb == 1'b1) ? 'd1022 : 'd1023;

  // GRS rounding of temp_mant
  // G=0, less than 0.5, so do not change
  // G=1, S=0, equal to 0.5, change based on LSB (LEB=0 -> inc, else -> no change)
  // G=1, S=1, greater than 0.5, so inc.
  assign temp_mant_lsb_bit    = (temp_mant_msb == 1'b1) ? temp_mant[104-52+1]  : temp_mant[103-52+1];
  assign temp_mant_guard_bit  = (temp_mant_msb == 1'b1) ? temp_mant[104-52]    : temp_mant[103-52];
  assign temp_mant_sticky_bit = (temp_mant_msb == 1'b1) ? |temp_mant[104-53:0] : |temp_mant[103-53:0];
  assign temp_mant_grs        = (temp_mant_guard_bit == 1'b0)  ? 1'b0 : 
                                (temp_mant_sticky_bit == 1'b1) ? 1'b1 : 
                                (temp_mant_lsb_bit == 1'b1)    ? 1'b1 : 1'b0;

  assign temp_exp_extended = in1_exp + in2_exp - temp_exp_adjust; // kept for the DEBUG print

  // Round. If the mantissa is all ones and rounds up, it carries out to 10.000...0:
  // the mantissa field becomes 0 and the exponent must go up by 1.
  assign temp_mant_truncated = (temp_mant_msb == 1'b1) ? temp_mant[104-:52] : temp_mant[103-:52];
  assign temp_mant_rounded   = {1'b0, temp_mant_truncated} + {52'd0, temp_mant_grs};
  assign temp_mant_round_ovf = temp_mant_rounded[52];

  // Biased exponent = e1 + e2 - 1023 (+1 if the product was >= 2.0, +1 if rounding carried out).
  // 11-bit (mod 2048) arithmetic gives the right answer whenever the result is in the normal range.
  assign temp_exp_final = in1_exp + in2_exp - 11'd1023 + {10'd0, temp_mant_msb} + {10'd0, temp_mant_round_ovf};

  assign out_sign = in1_sign ^ in2_sign;
  assign out_exp  = temp_exp_final;
  assign out_mant = temp_mant_rounded[51:0];

  // Scope (matches FALCON's needs): inputs are zero or normal, results stay in the normal
  // range. Inf, NaN, subnormals and exponent overflow/underflow are not handled.
  // Zero is not an exception: 0 * x must be 0, so it is still detected here.
  assign out_tdata = (in1_is_zero | in2_is_zero) ? {out_sign, 63'd0} : {out_sign, out_exp, out_mant};


  // Output
  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_mul_out_tvalid_reg <= 1'b0;
      fpr_mul_out_tdata_reg <= 64'b0;
    end else begin
      fpr_mul_out_tvalid_reg <= fpr_mul_in_tvalid;
      fpr_mul_out_tdata_reg <= out_tdata;
    end
  end

  assign fpr_mul_out_tvalid = fpr_mul_out_tvalid_reg;
  assign fpr_mul_out_tdata = fpr_mul_out_tdata_reg;

  // Debug
  always@ (posedge clk) begin
    if (~rst_n) begin
      cycle_count <= 16'b0;
    end else if (fpr_mul_in_tvalid) begin
      cycle_count <= cycle_count + 1'b1;
      if (DEBUG == 1) begin
        $display("cycle_count        =  %d \t\t=  0x%h\n",   cycle_count, cycle_count);
        $display("in1_sign           =  %d \t\t=  0x%h",     in1_sign, in1_sign);
        $display("in1_exp            =  %d \t\t=  0x%h",     in1_exp, in1_exp);
        $display("in1_mant           =  %d \t\t=  0x%h",     in1_mant, in1_mant);
        $display("in1_mant_extended  =  %d \t\t=  0x%h\n",   in1_mant_extended, in1_mant_extended);
        $display("in2_sign           =  %d \t\t=  0x%h",     in2_sign, in2_sign);
        $display("in2_exp            =  %d \t\t=  0x%h",     in2_exp, in2_exp);
        $display("in2_mant           =  %d \t\t=  0x%h",     in2_mant, in2_mant);
        $display("in2_mant_extended  =  %d \t\t=  0x%h\n",   in2_mant_extended, in2_mant_extended);
        $display("uint64_mult_in1    =  %d \t\t=  0x%h",     uint64_mult_in1, uint64_mult_in1);
        $display("uint64_mult_in2    =  %d \t\t=  0x%h",     uint64_mult_in2, uint64_mult_in2);
        $display("uint64_mult_result =  %d \t\t=  0x%h\n",   uint64_mult_result, uint64_mult_result);
        $display("temp_mant          =  %d \t\t=  0x%h",     temp_mant, temp_mant);
        $display("temp_mant_msb      =  %d \t\t=  0x%h",     temp_mant_msb, temp_mant_msb);
        $display("temp_exp_adjust    =  %d \t\t=  0x%h",     temp_exp_adjust, temp_exp_adjust);
        $display("temp_exp_extended  =  %d \t\t=  0x%h\n\n", temp_exp_extended, temp_exp_extended);
      end
    end
  end

endmodule