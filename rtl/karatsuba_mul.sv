
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

// Unsigned N x N -> 2N multiplier, recursive Karatsuba, combinational (0 latency).
//   a = a_hi * 2^L + a_lo,  b = b_hi * 2^L + b_lo
//   z2 = a_hi * b_hi,  z0 = a_lo * b_lo
//   z1 = (a_hi + a_lo) * (b_hi + b_lo) - z2 - z0
//   a * b = z2 * 2^(2L) + z1 * 2^L + z0
// 3 sub-multiplies per level instead of 4. Recursion stops at N <= BASE, where a
// plain multiply is used (pick BASE to match the DSP size, e.g. 18 for 18x18 or
// 17 for unsigned use of 18x18 signed DSPs). BASE must be >= 3.
`include "defines.vh"

module karatsuba_mul #(
  parameter N    = 64,
  parameter BASE = 18
) (
  input  wire [N-1:0]   a,
  input  wire [N-1:0]   b,
  output wire [2*N-1:0] p
);

  generate
    if (N <= BASE) begin : gen_base
      assign p = a * b;
    end else begin : gen_split
      localparam L = N / 2;  // low part width
      localparam H = N - L;  // high part width, H >= L

      wire [H-1:0]   a_hi, b_hi;
      wire [L-1:0]   a_lo, b_lo;
      wire [H:0]     a_sum, b_sum;
      wire [2*H-1:0] z2;
      wire [2*L-1:0] z0;
      wire [2*H+1:0] z1_full;
      wire [2*H+1:0] z1;

      assign a_hi  = a[N-1:L];
      assign a_lo  = a[L-1:0];
      assign b_hi  = b[N-1:L];
      assign b_lo  = b[L-1:0];
      assign a_sum = a_hi + a_lo;
      assign b_sum = b_hi + b_lo;

      karatsuba_mul #(
        .N    (H),
        .BASE (BASE)
      ) karatsuba_mul_hi (
        .a (a_hi),
        .b (b_hi),
        .p (z2)
      );

      karatsuba_mul #(
        .N    (L),
        .BASE (BASE)
      ) karatsuba_mul_lo (
        .a (a_lo),
        .b (b_lo),
        .p (z0)
      );

      karatsuba_mul #(
        .N    (H + 1),
        .BASE (BASE)
      ) karatsuba_mul_mid (
        .a (a_sum),
        .b (b_sum),
        .p (z1_full)
      );

      // z1 = a_hi * b_lo + a_lo * b_hi, never negative
      assign z1 = z1_full - z2 - z0;
      assign p  = (z2 << (2 * L)) + (z1 << L) + z0;
    end
  endgenerate

endmodule
