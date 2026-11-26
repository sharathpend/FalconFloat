
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`include "defines.vh"

// Accumulating multiply-add built on fpr_fma:
//   acc <= (+/-)(a * b) + (+/-)acc      op[1] negates a * b, op[0] negates acc
//   acc_clear = 1 starts a new sum:  acc <= (+/-)(a * b)
// The accumulator is the fpr_fma output register (fpr_mac_out_tdata).
// FUSED, REG_STAGES and INTERNAL_MULT are passed to fpr_fma.
// REG_STAGES = 1: one input per cycle.
// REG_STAGES = 2: the result feeds back into the next input, so in_tready drops for
//                 the cycle after each accepted input (one input every 2 cycles).
// An input is accepted when in_tvalid & in_tready.
module fpr_mac #(
  parameter DEBUG         = 0,
  parameter FUSED         = 1,
  parameter REG_STAGES    = 1,
  parameter INTERNAL_MULT = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_mac_in_tvalid,
  output wire         fpr_mac_in_tready,
  input  wire [63:0]  fpr_mac_in1_tdata,    // a
  input  wire [63:0]  fpr_mac_in2_tdata,    // b
  input  wire [1:0]   fpr_mac_op,           // [1]: negate a * b, [0]: negate acc
  input  wire         fpr_mac_in_acc_clear, // 1: ignore acc, acc <= (+/-)(a * b)

  // to-from shared multiplier
  output wire [63:0]  uint64_mult_in1,
  output wire [63:0]  uint64_mult_in2,
  input  wire [127:0] uint64_mult_result,

  output wire         fpr_mac_out_tvalid,
  output wire [63:0]  fpr_mac_out_tdata     // accumulator
);

  wire        accept;
  wire [63:0] acc;
  wire [63:0] addend;

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg busy_reg = 0;
  `else
    (* dont_touch = "true" *) reg busy_reg;
  `endif

  assign fpr_mac_in_tready = (REG_STAGES == 2) ? ~busy_reg : 1'b1;
  assign accept            = fpr_mac_in_tvalid & fpr_mac_in_tready;

  // Cleared accumulator = -0 after op[0], since x + (-0) = x for every x, including -0.
  assign addend = fpr_mac_in_acc_clear ? {~fpr_mac_op[0], 63'd0} : acc;

  fpr_fma #(
    .DEBUG         (DEBUG),
    .FUSED         (FUSED),
    .REG_STAGES    (REG_STAGES),
    .INTERNAL_MULT (INTERNAL_MULT)
  ) fpr_fma_inst (
    .clk                (clk),
    .rst_n              (rst_n),

    .fpr_fma_in_tvalid  (accept),
    .fpr_fma_in1_tdata  (fpr_mac_in1_tdata),
    .fpr_fma_in2_tdata  (fpr_mac_in2_tdata),
    .fpr_fma_in3_tdata  (addend),
    .fpr_fma_op         (fpr_mac_op),

    .uint64_mult_in1    (uint64_mult_in1),
    .uint64_mult_in2    (uint64_mult_in2),
    .uint64_mult_result (uint64_mult_result),

    .fpr_fma_out_tvalid (fpr_mac_out_tvalid),
    .fpr_fma_out_tdata  (acc)
  );

  always@ (posedge clk) begin
    if (~rst_n) begin
      busy_reg <= 1'b0;
    end else begin
      busy_reg <= (REG_STAGES == 2) & accept;
    end
  end

  assign fpr_mac_out_tdata = acc;

endmodule
