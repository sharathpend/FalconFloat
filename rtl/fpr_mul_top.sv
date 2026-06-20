
// Just the multipliers
`include "defines.vh"

module fpr_mul_top #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_mul_in_tvalid,
  input  wire [63:0]  fpr_mul_in1_tdata,
  input  wire [63:0]  fpr_mul_in2_tdata,
  input  wire         fpr_mul_op, // 0 = fp mul, 1 = int64 mul

  output wire         fpr_mul_out_tvalid,
  output wire [63:0]  fpr_mul_out_tdata,
  
  output wire         int64_mul_out_tvalid,
  output wire [127:0] int64_mul_out_tdata
  
);

  // shared multiplier
  wire [63:0]  uint64_mult_in1;
  wire [63:0]  uint64_mult_in2;
  wire [127:0] uint64_mult_result;

  wire [63:0]  fpr_mul_uint64_mult_in1;
  wire [63:0]  fpr_mul_uint64_mult_in2;

  wire [63:0]  int64_mul_uint64_mult_in1;
  wire [63:0]  int64_mul_uint64_mult_in2;

  // FPR Multiplication
  fpr_mul #(
    .DEBUG (DEBUG)
  ) fpr_mul_inst (
    .clk                (clk),
    .rst_n              (rst_n),

    .fpr_mul_in_tvalid  (fpr_mul_in_tvalid && (fpr_mul_op == 1'b0)),
    .fpr_mul_in1_tdata  (fpr_mul_in1_tdata),
    .fpr_mul_in2_tdata  (fpr_mul_in2_tdata),

    // to-from shared multiplier
    .uint64_mult_in1    (fpr_mul_uint64_mult_in1),
    .uint64_mult_in2    (fpr_mul_uint64_mult_in2),
    .uint64_mult_result (uint64_mult_result),

    .fpr_mul_out_tvalid (fpr_mul_out_tvalid),
    .fpr_mul_out_tdata  (fpr_mul_out_tdata)
  );

  // Signed INT64 Multiplication
  int64_mul #(
    .DEBUG (DEBUG)
  ) int64_mul_inst (
    .clk                  (clk),
    .rst_n                (rst_n),

    .int64_mul_in_tvalid  (fpr_mul_in_tvalid && (fpr_mul_op == 1'b1)),
    .int64_mul_in1_tdata  (fpr_mul_in1_tdata),
    .int64_mul_in2_tdata  (fpr_mul_in2_tdata),

    // to-from shared multiplier
    .uint64_mult_in1      (int64_mul_uint64_mult_in1),
    .uint64_mult_in2      (int64_mul_uint64_mult_in2),
    .uint64_mult_result   (uint64_mult_result),

    .int64_mul_out_tvalid (int64_mul_out_tvalid),
    .int64_mul_out_tdata  (int64_mul_out_tdata)
);

  // Common 64-bit unsigned integer multiplier. Can be replaced with custom multiplier as needed.
  // Karatsuba and comba code used is by magesh et al., modified for 0 latency
  assign uint64_mult_in1 = (fpr_mul_op == 1'b0) ? fpr_mul_uint64_mult_in1 : int64_mul_uint64_mult_in1;
  assign uint64_mult_in2 = (fpr_mul_op == 1'b0) ? fpr_mul_uint64_mult_in2 : int64_mul_uint64_mult_in2;

  `ifdef DEFAULT_MUL
    assign uint64_mult_result = uint64_mult_in1 * uint64_mult_in2;
  `endif

endmodule