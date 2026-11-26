
`define FPGA_DESIGN
`define MASK_USING_BARREL_SHIFTER // if not defined, use priority encoder in int2fpr

// Choose the multiplier below (or define one on the tool command line, e.g. -DKARATSUBA_MUL).
// It is used through uint_mul_core by the top levels and by INTERNAL_MULT = 1 units.

//`define KARATSUBA_MUL
//`define COMBA_MUL
`ifndef KARATSUBA_MUL
  `ifndef COMBA_MUL
    `define DEFAULT_MUL
  `endif
`endif