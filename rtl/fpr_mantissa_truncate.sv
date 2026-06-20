
// Take an input mantissa, shift it right performing GRS rounding.
// The output is full size, and the correct bits have to be picked up externally.
`include "defines.vh"

module fpr_mantissa_truncate #(
  parameter MANTISSA_BITS = 106, // size of mantissa
  parameter SHIFT_WIDTH = 54 // how many bits to shift right
) (
  input  wire [MANTISSA_BITS-1:0] mantissa_in,

  output wire [MANTISSA_BITS-1:0] mantissa_out
);

  wire  guard_bit;
  wire  sticky_bit;
  wire  lsb_of_result;
  wire  round_up;

  generate
    if (SHIFT_WIDTH == 0) begin
      assign mantissa_out = mantissa_in;
    end else if (SHIFT_WIDTH >= MANTISSA_BITS) begin
      assign mantissa_out = 0;
    end else begin
      assign lsb_of_result = mantissa_in[SHIFT_WIDTH];
      assign guard_bit = mantissa_in[SHIFT_WIDTH-1];
      assign sticky_bit = |mantissa_in[(SHIFT_WIDTH-2):0];
      assign round_up = guard_bit & (sticky_bit | lsb_of_result);
      assign mantissa_out = (mantissa_in >> SHIFT_WIDTH) + round_up;
    end
  endgenerate

endmodule