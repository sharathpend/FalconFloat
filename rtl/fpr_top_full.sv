
// all FPU
`include "defines.vh"

module fpr_top_full #(
  parameter DEBUG = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         in_tvalid,
  input  wire [63:0]  in1_tdata,
  input  wire [63:0]  in2_tdata,
  input  wire [4:0]   op, // 5'bXXXX1 = add, 5'bXXX10 = floor, 5'bXX100 = int2fp, 5'bX1000 = fp_mul, 5'b10000 = int_mul

  output wire         out_tvalid,
  output wire [63:0]  out_tdata,
  
  output wire         int64_mul_out_tvalid,
  output wire [127:0] int64_mul_out_tdata
);

  wire        fpr_add_out_tvalid;
  wire [63:0] fpr_add_out_tdata;

  wire        fpr_floor_out_tvalid;
  wire [63:0] fpr_floor_out_tdata;

  wire        int2fpr_out_tvalid;
  wire [63:0] int2fpr_out_tdata;
  
  wire        fpr_mul_out_tvalid;
  wire [63:0] fpr_mul_out_tdata;

  // shared multiplier
  wire [63:0]  uint64_mult_in1;
  wire [63:0]  uint64_mult_in2;
  wire [127:0] uint64_mult_result;

  wire [63:0]  fpr_mul_uint64_mult_in1;
  wire [63:0]  fpr_mul_uint64_mult_in2;

  wire [63:0]  int64_mul_uint64_mult_in1;
  wire [63:0]  int64_mul_uint64_mult_in2;


  // FPR Addition
  fpr_add #(
    .DEBUG (DEBUG)
  ) fpr_add_inst (
    .clk                (clk),
    .rst_n              (rst_n),

    .fpr_add_in_tvalid  (in_tvalid && op[0]),
    .fpr_add_in1_tdata  (in1_tdata),
    .fpr_add_in2_tdata  (in2_tdata),

    .fpr_add_out_tvalid (fpr_add_out_tvalid),
    .fpr_add_out_tdata  (fpr_add_out_tdata)
  );

  // FPR Floor (round to -INF)
  fpr_floor #(
    .DEBUG (DEBUG)
  ) fpr_floor_inst (
    .clk                  (clk),
    .rst_n                (rst_n),

    .fpr_floor_in_tvalid  (in_tvalid && op[1]),
    .fpr_floor_in_tdata   (in1_tdata),

    .fpr_floor_out_tvalid (fpr_floor_out_tvalid),
    .fpr_floor_out_tdata  (fpr_floor_out_tdata)
  );

  // INT to FPR
  int2fpr #(
    .DEBUG (DEBUG)
  ) int2fpr_inst (
    .clk                (clk),
    .rst_n              (rst_n),

    .int2fpr_in_tvalid  (in_tvalid && op[2]),
    .int2fpr_in_tdata   (in1_tdata),

    .int2fpr_out_tvalid (int2fpr_out_tvalid),
    .int2fpr_out_tdata  (int2fpr_out_tdata)
  );

  // FPR Multiplication
  fpr_mul #(
    .DEBUG (DEBUG)
  ) fpr_mul_inst (
    .clk                (clk),
    .rst_n              (rst_n),

    .fpr_mul_in_tvalid  (in_tvalid && op[3]),
    .fpr_mul_in1_tdata  (in1_tdata),
    .fpr_mul_in2_tdata  (in2_tdata),

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

    .int64_mul_in_tvalid  (in_tvalid && op[4]),
    .int64_mul_in1_tdata  (in1_tdata),
    .int64_mul_in2_tdata  (in2_tdata),

    // to-from shared multiplier
    .uint64_mult_in1      (int64_mul_uint64_mult_in1),
    .uint64_mult_in2      (int64_mul_uint64_mult_in2),
    .uint64_mult_result   (uint64_mult_result),

    .int64_mul_out_tvalid (int64_mul_out_tvalid),
    .int64_mul_out_tdata  (int64_mul_out_tdata)
);

  // Common 64-bit unsigned integer multiplier. Can be replaced with custom multiplier as needed.
  // Karatsuba and comba code used is by magesh et al., modified for 0 latency
  assign uint64_mult_in1 = (op[3] == 1'b1) ? fpr_mul_uint64_mult_in1 : int64_mul_uint64_mult_in1;
  assign uint64_mult_in2 = (op[3] == 1'b1) ? fpr_mul_uint64_mult_in2 : int64_mul_uint64_mult_in2;

  `ifdef DEFAULT_MUL
    assign uint64_mult_result = uint64_mult_in1 * uint64_mult_in2;
  `endif


  // Output MUX
  assign out_tvalid = (op[0] == 1'b1) ? fpr_add_out_tvalid    : 
                      (op[1] == 1'b1) ? fpr_floor_out_tvalid  : 
                      (op[2] == 1'b1) ? int2fpr_out_tvalid    : 
                      (op[3] == 1'b1) ? fpr_mul_out_tvalid    : 'd0;
  
  assign out_tdata =  (op[0] == 1'b1) ? fpr_add_out_tdata    : 
                      (op[1] == 1'b1) ? fpr_floor_out_tdata  : 
                      (op[2] == 1'b1) ? int2fpr_out_tdata    : 
                      (op[3] == 1'b1) ? fpr_mul_out_tdata    : 'd0;

endmodule