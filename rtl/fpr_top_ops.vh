
// Op codes for fpr_top (in_op / out_op). Results: out_tdata, plus out_tdata2/3 where noted.
`ifndef FPR_TOP_OPS_VH
`define FPR_TOP_OPS_VH

`define FPR_OP_ADD        5'h00 // a + b
`define FPR_OP_SUB        5'h01 // a - b
`define FPR_OP_MUL        5'h02 // a * b
`define FPR_OP_FMA        5'h03 // a * b + c
`define FPR_OP_FMS        5'h04 // a * b - c
`define FPR_OP_FNMA       5'h05 // -a * b + c
`define FPR_OP_FNMS       5'h06 // -a * b - c
`define FPR_OP_FLOOR      5'h08 // int64 / double / residue of floor(a)
`define FPR_OP_CEIL       5'h09 // ... ceil(a)
`define FPR_OP_TRUNC      5'h0A // ... trunc(a)
`define FPR_OP_ROUND      5'h0B // ... round(a), nearest, ties to even
`define FPR_OP_INT2FPR    5'h0C // double(a), a = signed int64
`define FPR_OP_DIV        5'h10 // a / b
`define FPR_OP_INV        5'h11 // 1 / a
`define FPR_OP_SQRT       5'h12 // sqrt(a)
`define FPR_OP_INT64_MUL  5'h14 // {sign, 0, |a[62:0]| * |b[62:0]|}: tdata = low 64, tdata2 = high 64
`define FPR_OP_UINT64_MUL 5'h15 // a * b unsigned, 128 bits: tdata = low 64, tdata2 = high 64

`endif
