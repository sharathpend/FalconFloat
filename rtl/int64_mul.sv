
// int64 multiplication. Can be used for ffsampling and ApproxExp MAC

  // for ApproxExp,
  // z,y 64 bit uint64 [0, 1, ... , (2^63)-1]
  // z.y guaranteed to fit in 126 bits (spec), and we need top 63 bits without rounding the dropped bits
  // z.y = {1'b0, 1'b0, [125:63], [62:0]}
  // y = C[u] - ((z.y)>>63)
  // (x.y)>>63 = [125:63] == (125-63+1) bits = 63b. So set MSB to 0.
  // so use 125:63 if you plan to use it for ApproxExp after the right shift.
  
`include "defines.vh"

module int64_mul #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         int64_mul_in_tvalid,
  input  wire [63:0]  int64_mul_in1_tdata,
  input  wire [63:0]  int64_mul_in2_tdata,

  // to-from shared multiplier
  output wire [63:0]  uint64_mult_in1,
  output wire [63:0]  uint64_mult_in2,
  input  wire [127:0] uint64_mult_result,

  output wire         int64_mul_out_tvalid,
  output wire [127:0] int64_mul_out_tdata
);

  wire result_sign;

  assign uint64_mult_in1 = {1'b0, int64_mul_in1_tdata[62:0]};
  assign uint64_mult_in2 = {1'b0, int64_mul_in2_tdata[62:0]};

  assign result_sign = int64_mul_in1_tdata[63] ^ int64_mul_in2_tdata[63];

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg          int64_mul_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [127:0] int64_mul_out_tdata_reg = 0;
  `else
    (* dont_touch = "true" *) reg          int64_mul_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [127:0] int64_mul_out_tdata_reg;
  `endif

  // Scaling as per FALCON's ApproxExp
  // z,y 64 bit uint64 [0, 1, ... , (2^63)-1]
  // z.y guaranteed to fit in 126 bits, and we need top 63 bits without rounding the dropped bits
  // z.y = {1'b0, 1'b0, [125:63], [62:0]}
  // y = C[u] - ((z.y)>>63)
  // (x.y)>>63 = [125:63] == (125-63+1) bits = 63b. So set MSB to 0.

  always@ (posedge clk) begin
    if (~rst_n) begin
      int64_mul_out_tvalid_reg <= 1'b0;
      int64_mul_out_tdata_reg <= 128'b0;
    end else begin
      int64_mul_out_tvalid_reg <= int64_mul_in_tvalid;
      int64_mul_out_tdata_reg  <= {result_sign, 1'b0, uint64_mult_result[125:0]};
    end
  end

  assign int64_mul_out_tdata  = int64_mul_out_tdata_reg;
  assign int64_mul_out_tvalid = int64_mul_out_tvalid_reg;

endmodule