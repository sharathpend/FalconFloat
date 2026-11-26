
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

// Unsigned N x N -> 2N multiplier, Comba (product scanning), combinational (0 latency).
// a and b are split into K = ceil(N / LIMB) limbs. Output limb k is the low LIMB bits
// of column k:
//   col[k] = sum over i + j = k of a[i] * b[j], plus the carry from col[k-1]
// and the rest of col[k] carries into col[k+1]. Each limb product is a
// LIMB x LIMB multiply (pick LIMB to match the DSP size, e.g. 16 or 17).
`include "defines.vh"

module comba_mul #(
  parameter N    = 64,
  parameter LIMB = 16
) (
  input  wire [N-1:0]   a,
  input  wire [N-1:0]   b,
  output wire [2*N-1:0] p
);

  localparam K     = (N + LIMB - 1) / LIMB;
  localparam ACC_W = 2 * LIMB + $clog2(K + 1) + 1; // K products + carry

  wire [K*LIMB-1:0]   a_pad;
  wire [K*LIMB-1:0]   b_pad;
  reg  [2*K*LIMB-1:0] p_pad;

  reg  [ACC_W-1:0]    col;
  reg  [ACC_W-1:0]    carry;
  integer             k, i;

  assign a_pad = a; // zero extended
  assign b_pad = b;

  always@ (*) begin
    carry = {ACC_W{1'b0}};
    p_pad = {(2*K*LIMB){1'b0}};
    for (k = 0; k < 2*K - 1; k = k + 1) begin
      col = carry;
      for (i = 0; i < K; i = i + 1) begin
        if ((k - i >= 0) && (k - i < K))
          col = col + a_pad[i*LIMB +: LIMB] * b_pad[(k-i)*LIMB +: LIMB];
      end
      p_pad[k*LIMB +: LIMB] = col[LIMB-1:0];
      carry = col >> LIMB;
    end
    p_pad[(2*K-1)*LIMB +: LIMB] = carry[LIMB-1:0];
  end

  assign p = p_pad[2*N-1:0];

endmodule
