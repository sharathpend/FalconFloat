
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

// fpr_fma with the common 64-bit unsigned multiplier attached (as in fpr_mul_top).
// The multiplier (default, Karatsuba or Comba) is chosen in defines.vh.
`include "defines.vh"

module fpr_fma_top #(
  parameter DEBUG      = 0,
  parameter FUSED      = 1,
  parameter REG_STAGES = 1
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_fma_in_tvalid,
  input  wire [63:0]  fpr_fma_in1_tdata,
  input  wire [63:0]  fpr_fma_in2_tdata,
  input  wire [63:0]  fpr_fma_in3_tdata,
  input  wire [1:0]   fpr_fma_op,

  output wire         fpr_fma_out_tvalid,
  output wire [63:0]  fpr_fma_out_tdata
);

  wire [63:0]  uint64_mult_in1;
  wire [63:0]  uint64_mult_in2;
  wire [127:0] uint64_mult_result;

  fpr_fma #(
    .DEBUG         (DEBUG),
    .FUSED         (FUSED),
    .REG_STAGES    (REG_STAGES),
    .INTERNAL_MULT (0)
  ) fpr_fma_inst (
    .clk                (clk),
    .rst_n              (rst_n),

    .fpr_fma_in_tvalid  (fpr_fma_in_tvalid),
    .fpr_fma_in1_tdata  (fpr_fma_in1_tdata),
    .fpr_fma_in2_tdata  (fpr_fma_in2_tdata),
    .fpr_fma_in3_tdata  (fpr_fma_in3_tdata),
    .fpr_fma_op         (fpr_fma_op),

    .uint64_mult_in1    (uint64_mult_in1),
    .uint64_mult_in2    (uint64_mult_in2),
    .uint64_mult_result (uint64_mult_result),

    .fpr_fma_out_tvalid (fpr_fma_out_tvalid),
    .fpr_fma_out_tdata  (fpr_fma_out_tdata)
  );

  // Implementation chosen in defines.vh
  uint_mul_core #(
    .N (64)
  ) uint_mul_core_inst (
    .a (uint64_mult_in1),
    .b (uint64_mult_in2),
    .p (uint64_mult_result)
  );

endmodule
