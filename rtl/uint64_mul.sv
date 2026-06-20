
// uint64 multiplication. Can be used for ffsampling
// with external unsign and sign conversion logic and
// for ApproxExp mac

  // for ApproxExp,
  // z,y 64 bit uint64 [0, 1, ... , (2^63)-1]
  // z.y guaranteed to fit in 126 bits (spec), and we need top 63 bits without rounding the dropped bits
  // z.y = {1'b0, 1'b0, [125:63], [62:0]}
  // y = C[u] - ((z.y)>>63)
  // (x.y)>>63 = [125:63] == (125-63+1) bits = 63b. So set MSB to 0.
  // so use 125:63 if you plan to use it for ApproxExp after the right shift.

`include "defines.vh"

module uint64_mul #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         uint64_mul_in_tvalid,
  input  wire [63:0]  uint64_mul_in1_tdata,
  input  wire [63:0]  uint64_mul_in2_tdata,

  // to-from shared multiplier
  output wire [63:0]  uint64_mult_in1,
  output wire [63:0]  uint64_mult_in2,
  input  wire [127:0] uint64_mult_result,

  output wire         uint64_mul_out_tvalid,
  output wire [127:0] uint64_mul_out_tdata
);

  assign uint64_mult_in1 = uint64_mul_in1_tdata;
  assign uint64_mult_in2 = uint64_mul_in2_tdata;


  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg          uint64_mul_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [127:0] uint64_mul_out_tdata_reg = 0;
  `else
    (* dont_touch = "true" *) reg          uint64_mul_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [127:0] uint64_mul_out_tdata_reg;
  `endif

  always@ (posedge clk) begin
    if (~rst_n) begin
      uint64_mul_out_tvalid_reg <= 1'b0;
      uint64_mul_out_tdata_reg <= 128'b0;
    end else begin
      uint64_mul_out_tvalid_reg <= uint64_mul_in_tvalid;
      uint64_mul_out_tdata_reg  <= uint64_mult_result;
    end
  end

  assign uint64_mul_out_tvalid = uint64_mul_out_tvalid_reg;
  assign uint64_mul_out_tdata  = uint64_mul_out_tdata_reg;

endmodule