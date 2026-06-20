
// all but multipliers
`include "defines.vh"

module fpr_top_partial #(
  parameter DEBUG = 0
) (
  input  wire        clk,
  input  wire        rst_n,

  input  wire        in_tvalid,
  input  wire [63:0] in1_tdata,
  input  wire [63:0] in2_tdata,
  input  wire [2:0]  op, // 3'bXX1 = add, 3'bX10 = floor, 3'b100 = int2fp

  output wire        out_tvalid,
  output wire [63:0] out_tdata
);

  wire        fpr_add_out_tvalid;
  wire [63:0] fpr_add_out_tdata;

  wire        fpr_floor_out_tvalid;
  wire [63:0] fpr_floor_out_tdata;

  wire        int2fpr_out_tvalid;
  wire [63:0] int2fpr_out_tdata;



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


  // Output MUX
  assign out_tvalid = (op[0] == 1'b1) ? fpr_add_out_tvalid    : 
                      (op[1] == 1'b1) ? fpr_floor_out_tvalid  : 
                      (op[2] == 1'b1) ? int2fpr_out_tvalid    : 'd0;
  
  assign out_tdata =  (op[0] == 1'b1) ? fpr_add_out_tdata    : 
                      (op[1] == 1'b1) ? fpr_floor_out_tdata  : 
                      (op[2] == 1'b1) ? int2fpr_out_tdata    : 'd0;

endmodule