
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

// Unsigned N x N -> 2N multiplier, combinational (0 latency). The implementation
// is chosen in defines.vh:
//   KARATSUBA_MUL -> karatsuba_mul (KARATSUBA_BASE = size of the plain multiplies)
//   COMBA_MUL     -> comba_mul     (COMBA_LIMB = limb width)
//   DEFAULT_MUL   -> a * b, left to the synthesis tool
// Used by the top levels (N = 64, shared multiplier) and by fpr_mul / fpr_fma
// with INTERNAL_MULT = 1 (N = 53, mantissas only).
`include "defines.vh"

module uint_mul_core #(
  parameter N              = 64,
  parameter KARATSUBA_BASE = 18,
  parameter COMBA_LIMB     = 16
) (
  input  wire [N-1:0]   a,
  input  wire [N-1:0]   b,
  output wire [2*N-1:0] p
);

  `ifdef KARATSUBA_MUL
    karatsuba_mul #(
      .N    (N),
      .BASE (KARATSUBA_BASE)
    ) karatsuba_mul_inst (
      .a (a),
      .b (b),
      .p (p)
    );
  `elsif COMBA_MUL
    comba_mul #(
      .N    (N),
      .LIMB (COMBA_LIMB)
    ) comba_mul_inst (
      .a (a),
      .b (b),
      .p (p)
    );
  `else
    assign p = a * b;
  `endif

endmodule
