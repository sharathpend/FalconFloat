
// Tells the index of the first 1 in little endian.
// If input is 64'b0001_0000_0000_...._0000, I expected to see 60.
// The only special case it won't work for is 0, but since this is being used in int2fpr, it looks
// out for that special case
// If this is used anywhere else, you need to account for input = 0.
`include "defines.vh"

module leading_one_calc #(
  parameter DEBUG = 0,
  parameter N = 64, // the size of the data you are working with
  parameter N_BITS = 6 // log2(N) basically, how many bits you need to represent (N-1)
) (
  input  wire [N-1:0]       loc_din,
  output wire [N_BITS-1:0]  loc_dout
);

  generate
    if (N > 2) begin : gen_block_n_gt_2
      wire [N_BITS-2:0] loc_dout_upper;
      wire [N_BITS-2:0] loc_dout_lower;

      leading_one_calc #(
        .DEBUG (DEBUG),
        .N (N/2),
        .N_BITS (N_BITS-1)
      ) loc_inst_upper (
        .loc_din  (loc_din[(N-1):(N/2)]),
        .loc_dout (loc_dout_upper)
      );

      leading_one_calc #(
        .DEBUG (DEBUG),
        .N (N/2),
        .N_BITS (N_BITS-1)
      ) loc_inst_lower (
        .loc_din  (loc_din[(N/2)-1:0]),
        .loc_dout (loc_dout_lower)
      );

      assign loc_dout = (loc_din[(N-1):(N/2)] != 'd0) ? {1'b1, loc_dout_upper} : {1'b0, loc_dout_lower};
    end else begin : gen_block_n_eq_2
      assign loc_dout = (loc_din[1] == 1'b1) ? 1'b1 : 1'b0;
    end
  endgenerate

endmodule