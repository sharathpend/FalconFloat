
`define FPGA_DESIGN
`define MASK_USING_BARREL_SHIFTER // if not defined, use priority encoder in int2fpr

// Choose multiplier below. You need the required code for others. We used the one
// by Magesh et al., LightSec 2025.

//`define KARATSUBA_MUL
//`define COMBA_MUL
`define DEFAULT_MUL