
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

// Just the multipliers, sharing one 64x64 unsigned multiplier (uint_mul_core).
//   fpr_mul_op = 2'b00: fp mul     -> fpr_mul_out_*
//   fpr_mul_op = 2'b01: int64 mul  -> int64_mul_out_*  {sign, 1'b0, |a[62:0]| * |b[62:0]|}
//   fpr_mul_op = 2'b10: uint64 mul -> uint64_mul_out_* full 128-bit a * b
// A 1-bit op from older designs (0 / 1) still selects fp / int64 mul.
`include "defines.vh"

module fpr_mul_top #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_mul_in_tvalid,
  input  wire [63:0]  fpr_mul_in1_tdata,
  input  wire [63:0]  fpr_mul_in2_tdata,
  input  wire [1:0]   fpr_mul_op, // 2'b00 = fp mul, 2'b01 = int64 mul, 2'b10 = uint64 mul

  output wire         fpr_mul_out_tvalid,
  output wire [63:0]  fpr_mul_out_tdata,
  
  output wire         int64_mul_out_tvalid,
  output wire [127:0] int64_mul_out_tdata,

  output wire         uint64_mul_out_tvalid,
  output wire [127:0] uint64_mul_out_tdata
);

  // shared multiplier
  wire [63:0]  uint64_mult_in1;
  wire [63:0]  uint64_mult_in2;
  wire [127:0] uint64_mult_result;

  wire [63:0]  fpr_mul_uint64_mult_in1;
  wire [63:0]  fpr_mul_uint64_mult_in2;

  wire [63:0]  int64_mul_uint64_mult_in1;
  wire [63:0]  int64_mul_uint64_mult_in2;

  wire [63:0]  uint64_mul_uint64_mult_in1;
  wire [63:0]  uint64_mul_uint64_mult_in2;

  // FPR Multiplication
  fpr_mul #(
    .DEBUG (DEBUG)
  ) fpr_mul_inst (
    .clk                (clk),
    .rst_n              (rst_n),

    .fpr_mul_in_tvalid  (fpr_mul_in_tvalid && (fpr_mul_op == 2'b00)),
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

    .int64_mul_in_tvalid  (fpr_mul_in_tvalid && (fpr_mul_op == 2'b01)),
    .int64_mul_in1_tdata  (fpr_mul_in1_tdata),
    .int64_mul_in2_tdata  (fpr_mul_in2_tdata),

    // to-from shared multiplier
    .uint64_mult_in1      (int64_mul_uint64_mult_in1),
    .uint64_mult_in2      (int64_mul_uint64_mult_in2),
    .uint64_mult_result   (uint64_mult_result),

    .int64_mul_out_tvalid (int64_mul_out_tvalid),
    .int64_mul_out_tdata  (int64_mul_out_tdata)
  );

  // Unsigned UINT64 Multiplication, full 128-bit product
  uint64_mul #(
    .DEBUG (DEBUG)
  ) uint64_mul_inst (
    .clk                   (clk),
    .rst_n                 (rst_n),

    .uint64_mul_in_tvalid  (fpr_mul_in_tvalid && (fpr_mul_op == 2'b10)),
    .uint64_mul_in1_tdata  (fpr_mul_in1_tdata),
    .uint64_mul_in2_tdata  (fpr_mul_in2_tdata),

    // to-from shared multiplier
    .uint64_mult_in1       (uint64_mul_uint64_mult_in1),
    .uint64_mult_in2       (uint64_mul_uint64_mult_in2),
    .uint64_mult_result    (uint64_mult_result),

    .uint64_mul_out_tvalid (uint64_mul_out_tvalid),
    .uint64_mul_out_tdata  (uint64_mul_out_tdata)
  );

  // Common 64-bit unsigned integer multiplier, implementation chosen in defines.vh
  // (default, Karatsuba or Comba, see uint_mul_core).
  assign uint64_mult_in1 = (fpr_mul_op == 2'b00) ? fpr_mul_uint64_mult_in1   :
                           (fpr_mul_op == 2'b01) ? int64_mul_uint64_mult_in1 : uint64_mul_uint64_mult_in1;
  assign uint64_mult_in2 = (fpr_mul_op == 2'b00) ? fpr_mul_uint64_mult_in2   :
                           (fpr_mul_op == 2'b01) ? int64_mul_uint64_mult_in2 : uint64_mul_uint64_mult_in2;

  uint_mul_core #(
    .N (64)
  ) uint_mul_core_inst (
    .a (uint64_mult_in1),
    .b (uint64_mult_in2),
    .p (uint64_mult_result)
  );

endmodule