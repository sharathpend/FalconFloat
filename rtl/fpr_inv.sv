
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`include "defines.vh"

// Double reciprocal 1 / x, round to nearest even (bit-exact with FALCON's
// fpr_inv(x) = fpr_div(1.0, x)). fpr_div with the dividend tied to 1.0, so the
// synthesis tool can trim the dividend logic. Same parameters, latency and
// handshake as fpr_div.
// Scope: x is normal and 1 / x is normal (|x| < 2^1022).
module fpr_inv #(
  parameter DEBUG          = 0,
  parameter BITS_PER_CYCLE = 2,
  parameter PIPELINED      = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_inv_in_tvalid,
  output wire         fpr_inv_in_tready,
  input  wire [63:0]  fpr_inv_in_tdata,

  output wire         fpr_inv_out_tvalid,
  output wire [63:0]  fpr_inv_out_tdata
);

  fpr_div #(
    .DEBUG          (DEBUG),
    .BITS_PER_CYCLE (BITS_PER_CYCLE),
    .PIPELINED      (PIPELINED)
  ) fpr_div_inst (
    .clk                (clk),
    .rst_n              (rst_n),

    .fpr_div_in_tvalid  (fpr_inv_in_tvalid),
    .fpr_div_in_tready  (fpr_inv_in_tready),
    .fpr_div_in1_tdata  (64'h3FF0_0000_0000_0000), // 1.0
    .fpr_div_in2_tdata  (fpr_inv_in_tdata),

    .fpr_div_out_tvalid (fpr_inv_out_tvalid),
    .fpr_div_out_tdata  (fpr_inv_out_tdata)
  );

endmodule
