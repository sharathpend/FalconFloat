
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

// fpr_top: a configurable, general-purpose wrapper around the FalconFloat units, for
// trying them together. It is NOT tuned for any particular FALCON implementation:
// one op per cycle, one shared multiplier, and a generic output path. For a real
// design, pick the individual modules you need and connect them for your own
// schedule. See HOW_TO_USE_README.md.
//
// Ops (fpr_top_ops.vh): add, sub, mul, the 4 FMA forms, floor / ceil / trunc / round
// (int64 + double + residue), int2fpr, div, inv, sqrt, int64 and uint64 mul.
//
// Units are chosen with parameters:
//   INCLUDE_ADD, INCLUDE_MUL, INCLUDE_FMA  fpr_add, fpr_mul, fpr_fma (FUSED, FMA_REG_STAGES)
//   FMA_ONLY_CORE = 1                      no fpr_add / fpr_mul: add, sub and mul run on
//                                          fpr_fma (a * 1.0 + b, a * b + (-0)), still
//                                          bit-exact, smaller but slower
//   INCLUDE_TO_INT                         fpr_to_int (floor / ceil / trunc / round)
//   INCLUDE_INT2FPR                        int2fpr
//   INCLUDE_INT_MUL                        int64_mul and uint64_mul
//   DIVSQRT = 0 / 1 / 2                    none / fpr_div + fpr_sqrt / fpr_div_sqrt
//                                          (DIVSQRT_BITS_PER_CYCLE, DIVSQRT_PIPELINED)
// fpr_mul, fpr_fma, int64_mul and uint64_mul share one 64x64 multiplier (uint_mul_core,
// chosen in defines.vh). This is safe because only one op is accepted per cycle.
//
// Handshake and results:
//   An op is accepted when in_tvalid & in_tready. Every op has a fixed latency
//   (1 cycle; FMA_REG_STAGES for FMA ops; ITER + 2 or ITER + 1 for div / inv / sqrt).
//   At issue, the op reserves its output cycle, and in_tready is low if that cycle is
//   taken or the unit is busy, so results never collide. Results can come back out of
//   order, each with out_op and out_tuser (in_tuser passed through).
//   An op whose unit is not included is accepted and returns out_error = 1 after 1 cycle.
// OPERAND_ISOLATION = 1 holds the inputs of idle units at 0 (less switching).
`include "defines.vh"
`include "fpr_top_ops.vh"

module fpr_top #(
  parameter DEBUG                  = 0,
  parameter INCLUDE_ADD            = 1,
  parameter INCLUDE_MUL            = 1,
  parameter INCLUDE_FMA            = 1,
  parameter FMA_ONLY_CORE          = 0,
  parameter FUSED                  = 1,
  parameter FMA_REG_STAGES         = 1,
  parameter INCLUDE_TO_INT         = 1,
  parameter INCLUDE_INT2FPR        = 1,
  parameter INCLUDE_INT_MUL        = 1,
  parameter DIVSQRT                = 2,
  parameter DIVSQRT_BITS_PER_CYCLE = 2,
  parameter DIVSQRT_PIPELINED      = 0,
  parameter OPERAND_ISOLATION      = 1,
  parameter TUSER_W                = 8
) (
  input  wire               clk,
  input  wire               rst_n,

  input  wire               in_tvalid,
  output wire               in_tready,
  input  wire [4:0]         in_op,
  input  wire [TUSER_W-1:0] in_tuser,
  input  wire [63:0]        in1_tdata,  // a
  input  wire [63:0]        in2_tdata,  // b
  input  wire [63:0]        in3_tdata,  // c (FMA ops only)

  output wire               out_tvalid,
  output wire [4:0]         out_op,
  output wire [TUSER_W-1:0] out_tuser,
  output wire               out_error,  // op not supported by this configuration
  output wire [63:0]        out_tdata,  // result (int64 for floor..round, low 64 bits for int muls)
  output wire [63:0]        out_tdata2, // floor..round: double value, int muls: high 64 bits
  output wire [63:0]        out_tdata3  // floor..round: residue
);

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------
  localparam HAS_FMA = (INCLUDE_FMA != 0) || (FMA_ONLY_CORE != 0);
  localparam HAS_ADD = (INCLUDE_ADD != 0) && (FMA_ONLY_CORE == 0);
  localparam HAS_MUL = (INCLUDE_MUL != 0) && (FMA_ONLY_CORE == 0);
  localparam DS_ITER = (54 + DIVSQRT_BITS_PER_CYCLE - 1) / DIVSQRT_BITS_PER_CYCLE;
  localparam L_DS    = DIVSQRT_PIPELINED ? DS_ITER + 1 : DS_ITER + 2;
  localparam L_FMA   = FMA_REG_STAGES;
  localparam L_A     = (HAS_FMA && L_FMA > 1) ? L_FMA : 1;
  localparam MAXL    = (DIVSQRT != 0 && L_DS > L_A) ? L_DS : L_A;   // longest latency
  localparam LW      = $clog2(MAXL + 2);

  localparam [3:0] U_ERR   = 4'd0,
                   U_ADD   = 4'd1,
                   U_MUL   = 4'd2,
                   U_FMA   = 4'd3,
                   U_TOINT = 4'd4,
                   U_I2F   = 4'd5,
                   U_DIV   = 4'd6,  // fpr_div, or fpr_div_sqrt for div / inv / sqrt
                   U_SQRT  = 4'd7,  // fpr_sqrt (DIVSQRT = 1)
                   U_IMUL  = 4'd8,
                   U_UMUL  = 4'd9;

  localparam [63:0] FPR_ONE      = 64'h3FF0_0000_0000_0000;
  localparam [63:0] FPR_NEG_ZERO = 64'h8000_0000_0000_0000;

  // ---------------------------------------------------------------------------
  // Decode
  // ---------------------------------------------------------------------------
  reg  [3:0]    op_unit;
  reg  [LW-1:0] op_lat;
  reg           unit_ready;
  wire          accept;

  wire          div_tready, sqrt_tready;

  always@ (*) begin
    op_unit = U_ERR;
    case (in_op)
      `FPR_OP_ADD, `FPR_OP_SUB:  op_unit = FMA_ONLY_CORE ? U_FMA : (HAS_ADD ? U_ADD : U_ERR);
      `FPR_OP_MUL:               op_unit = FMA_ONLY_CORE ? U_FMA : (HAS_MUL ? U_MUL : U_ERR);
      `FPR_OP_FMA, `FPR_OP_FMS,
      `FPR_OP_FNMA, `FPR_OP_FNMS: op_unit = HAS_FMA ? U_FMA : U_ERR;
      `FPR_OP_FLOOR, `FPR_OP_CEIL,
      `FPR_OP_TRUNC, `FPR_OP_ROUND: op_unit = INCLUDE_TO_INT ? U_TOINT : U_ERR;
      `FPR_OP_INT2FPR:           op_unit = INCLUDE_INT2FPR ? U_I2F : U_ERR;
      `FPR_OP_DIV, `FPR_OP_INV:  op_unit = (DIVSQRT != 0) ? U_DIV : U_ERR;
      `FPR_OP_SQRT:              op_unit = (DIVSQRT == 1) ? U_SQRT : (DIVSQRT == 2) ? U_DIV : U_ERR;
      `FPR_OP_INT64_MUL:         op_unit = INCLUDE_INT_MUL ? U_IMUL : U_ERR;
      `FPR_OP_UINT64_MUL:        op_unit = INCLUDE_INT_MUL ? U_UMUL : U_ERR;
      default:                   op_unit = U_ERR;
    endcase

    case (op_unit)
      U_FMA:         op_lat = L_FMA;
      U_DIV, U_SQRT: op_lat = L_DS;
      default:       op_lat = 1;
    endcase

    case (op_unit)
      U_DIV:   unit_ready = div_tready;
      U_SQRT:  unit_ready = sqrt_tready;
      default: unit_ready = 1'b1;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Output cycle reservation. After a clock edge, slot_busy[j] = 1 means a result
  // comes out j cycles from now (slot 0 = this cycle's output).
  // ---------------------------------------------------------------------------
  `ifdef FPGA_DESIGN
    reg [MAXL:0]        slot_busy = 0;
  `else
    reg [MAXL:0]        slot_busy;
  `endif
  reg  [3:0]            slot_unit [0:MAXL];
  reg  [4:0]            slot_op   [0:MAXL];
  reg  [TUSER_W-1:0]    slot_user [0:MAXL];
  integer               j;

  assign in_tready = unit_ready & ~slot_busy[op_lat];
  assign accept    = in_tvalid & in_tready;

  always@ (posedge clk) begin
    if (~rst_n) begin
      slot_busy <= {(MAXL+1){1'b0}};
    end else begin
      for (j = 0; j < MAXL; j = j + 1) begin
        slot_busy[j] <= slot_busy[j+1];
        slot_unit[j] <= slot_unit[j+1];
        slot_op[j]   <= slot_op[j+1];
        slot_user[j] <= slot_user[j+1];
      end
      slot_busy[MAXL] <= 1'b0;
      if (accept) begin
        slot_busy[op_lat-1] <= 1'b1;
        slot_unit[op_lat-1] <= op_unit;
        slot_op[op_lat-1]   <= in_op;
        slot_user[op_lat-1] <= in_tuser;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Unit inputs: valid on accept, data held at 0 for idle units (OPERAND_ISOLATION)
  // ---------------------------------------------------------------------------
  wire sel_add   = in_tvalid & (op_unit == U_ADD);
  wire sel_mul   = in_tvalid & (op_unit == U_MUL);
  wire sel_fma   = in_tvalid & (op_unit == U_FMA);
  wire sel_toint = in_tvalid & (op_unit == U_TOINT);
  wire sel_i2f   = in_tvalid & (op_unit == U_I2F);
  wire sel_div   = in_tvalid & (op_unit == U_DIV);
  wire sel_sqrt  = in_tvalid & (op_unit == U_SQRT);
  wire sel_imul  = in_tvalid & (op_unit == U_IMUL);
  wire sel_umul  = in_tvalid & (op_unit == U_UMUL);

  wire [63:0] in1_iso_add   = (OPERAND_ISOLATION && !sel_add)   ? 64'd0 : in1_tdata;
  wire [63:0] in2_iso_add   = (OPERAND_ISOLATION && !sel_add)   ? 64'd0 : in2_tdata;
  wire [63:0] in1_iso_mul   = (OPERAND_ISOLATION && !sel_mul)   ? 64'd0 : in1_tdata;
  wire [63:0] in2_iso_mul   = (OPERAND_ISOLATION && !sel_mul)   ? 64'd0 : in2_tdata;
  wire [63:0] in1_iso_toint = (OPERAND_ISOLATION && !sel_toint) ? 64'd0 : in1_tdata;
  wire [63:0] in1_iso_i2f   = (OPERAND_ISOLATION && !sel_i2f)   ? 64'd0 : in1_tdata;
  wire [63:0] in1_iso_div   = (OPERAND_ISOLATION && !sel_div)   ? 64'd0 : in1_tdata;
  wire [63:0] in2_iso_div   = (OPERAND_ISOLATION && !sel_div)   ? 64'd0 : in2_tdata;
  wire [63:0] in1_iso_sqrt  = (OPERAND_ISOLATION && !sel_sqrt)  ? 64'd0 : in1_tdata;
  wire [63:0] in1_iso_imul  = (OPERAND_ISOLATION && !sel_imul)  ? 64'd0 : in1_tdata;
  wire [63:0] in2_iso_imul  = (OPERAND_ISOLATION && !sel_imul)  ? 64'd0 : in2_tdata;
  wire [63:0] in1_iso_umul  = (OPERAND_ISOLATION && !sel_umul)  ? 64'd0 : in1_tdata;
  wire [63:0] in2_iso_umul  = (OPERAND_ISOLATION && !sel_umul)  ? 64'd0 : in2_tdata;

  // FMA operands: add / sub as a * 1.0 +/- b, mul as a * b + (-0)
  wire        fma_is_addsub = (in_op == `FPR_OP_ADD) || (in_op == `FPR_OP_SUB);
  wire        fma_is_mul    = (in_op == `FPR_OP_MUL);
  wire [63:0] fma_a  = in1_tdata;
  wire [63:0] fma_b  = fma_is_addsub ? FPR_ONE : in2_tdata;
  wire [63:0] fma_c  = fma_is_addsub ? in2_tdata : fma_is_mul ? FPR_NEG_ZERO : in3_tdata;
  wire [1:0]  fma_op = fma_is_addsub ? {1'b0, (in_op == `FPR_OP_SUB)} :
                       fma_is_mul    ? 2'b00 :
                                       (in_op - `FPR_OP_FMA);         // FMA, FMS, FNMA, FNMS -> 0..3
  wire [63:0] fma_a_iso = (OPERAND_ISOLATION && !sel_fma) ? 64'd0 : fma_a;
  wire [63:0] fma_b_iso = (OPERAND_ISOLATION && !sel_fma) ? 64'd0 : fma_b;
  wire [63:0] fma_c_iso = (OPERAND_ISOLATION && !sel_fma) ? 64'd0 : fma_c;

  // ---------------------------------------------------------------------------
  // Shared 64x64 multiplier
  // ---------------------------------------------------------------------------
  wire [63:0]  mul_m1,  mul_m2;
  wire [63:0]  fma_m1,  fma_m2;
  wire [63:0]  imul_m1, imul_m2;
  wire [63:0]  umul_m1, umul_m2;
  wire [63:0]  uint64_mult_in1, uint64_mult_in2;
  wire [127:0] uint64_mult_result;

  assign uint64_mult_in1 = (op_unit == U_FMA)  ? fma_m1  :
                           (op_unit == U_MUL)  ? mul_m1  :
                           (op_unit == U_IMUL) ? imul_m1 : umul_m1;
  assign uint64_mult_in2 = (op_unit == U_FMA)  ? fma_m2  :
                           (op_unit == U_MUL)  ? mul_m2  :
                           (op_unit == U_IMUL) ? imul_m2 : umul_m2;

  generate
    if (HAS_MUL || HAS_FMA || INCLUDE_INT_MUL) begin : gen_mult
      uint_mul_core #(
        .N (64)
      ) uint_mul_core_inst (
        .a (uint64_mult_in1),
        .b (uint64_mult_in2),
        .p (uint64_mult_result)
      );
    end else begin : gen_no_mult
      assign uint64_mult_result = 128'd0;
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Units
  // ---------------------------------------------------------------------------
  wire [63:0]  add_out, mul_out, fma_out, i2f_out, div_out, sqrt_out;
  wire [63:0]  toint_int, toint_fpr, toint_res;
  wire [127:0] imul_out, umul_out;

  generate
    if (HAS_ADD) begin : gen_add
      fpr_add #(.DEBUG (DEBUG)) fpr_add_inst (
        .clk (clk), .rst_n (rst_n),
        .fpr_add_in_tvalid  (accept & sel_add),
        .fpr_add_in1_tdata  (in1_iso_add),
        .fpr_add_in2_tdata  ((in_op == `FPR_OP_SUB) ? {~in2_iso_add[63], in2_iso_add[62:0]} : in2_iso_add),
        .fpr_add_out_tvalid (),
        .fpr_add_out_tdata  (add_out)
      );
    end else begin : gen_no_add
      assign add_out = 64'd0;
    end

    if (HAS_MUL) begin : gen_mul
      fpr_mul #(.DEBUG (DEBUG), .INTERNAL_MULT (0)) fpr_mul_inst (
        .clk (clk), .rst_n (rst_n),
        .fpr_mul_in_tvalid  (accept & sel_mul),
        .fpr_mul_in1_tdata  (in1_iso_mul),
        .fpr_mul_in2_tdata  (in2_iso_mul),
        .uint64_mult_in1    (mul_m1),
        .uint64_mult_in2    (mul_m2),
        .uint64_mult_result (uint64_mult_result),
        .fpr_mul_out_tvalid (),
        .fpr_mul_out_tdata  (mul_out)
      );
    end else begin : gen_no_mul
      assign mul_out = 64'd0;
      assign mul_m1  = 64'd0;
      assign mul_m2  = 64'd0;
    end

    if (HAS_FMA) begin : gen_fma
      fpr_fma #(.DEBUG (DEBUG), .FUSED (FUSED), .REG_STAGES (FMA_REG_STAGES), .INTERNAL_MULT (0)) fpr_fma_inst (
        .clk (clk), .rst_n (rst_n),
        .fpr_fma_in_tvalid  (accept & sel_fma),
        .fpr_fma_in1_tdata  (fma_a_iso),
        .fpr_fma_in2_tdata  (fma_b_iso),
        .fpr_fma_in3_tdata  (fma_c_iso),
        .fpr_fma_op         (fma_op),
        .uint64_mult_in1    (fma_m1),
        .uint64_mult_in2    (fma_m2),
        .uint64_mult_result (uint64_mult_result),
        .fpr_fma_out_tvalid (),
        .fpr_fma_out_tdata  (fma_out)
      );
    end else begin : gen_no_fma
      assign fma_out = 64'd0;
      assign fma_m1  = 64'd0;
      assign fma_m2  = 64'd0;
    end

    if (INCLUDE_TO_INT) begin : gen_toint
      fpr_to_int #(.DEBUG (DEBUG)) fpr_to_int_inst (
        .clk (clk), .rst_n (rst_n),
        .fpr_to_int_in_tvalid   (accept & sel_toint),
        .fpr_to_int_in_tdata    (in1_iso_toint),
        .fpr_to_int_mode        (in_op[1:0]),               // FLOOR, CEIL, TRUNC, ROUND = 8..11
        .fpr_to_int_out_tvalid  (),
        .fpr_to_int_out_int     (toint_int),
        .fpr_to_int_out_fpr     (toint_fpr),
        .fpr_to_int_out_residue (toint_res)
      );
    end else begin : gen_no_toint
      assign toint_int = 64'd0;
      assign toint_fpr = 64'd0;
      assign toint_res = 64'd0;
    end

    if (INCLUDE_INT2FPR) begin : gen_i2f
      int2fpr #(.DEBUG (DEBUG)) int2fpr_inst (
        .clk (clk), .rst_n (rst_n),
        .int2fpr_in_tvalid  (accept & sel_i2f),
        .int2fpr_in_tdata   (in1_iso_i2f),
        .int2fpr_out_tvalid (),
        .int2fpr_out_tdata  (i2f_out)
      );
    end else begin : gen_no_i2f
      assign i2f_out = 64'd0;
    end

    if (INCLUDE_INT_MUL) begin : gen_int_mul
      int64_mul #(.DEBUG (DEBUG)) int64_mul_inst (
        .clk (clk), .rst_n (rst_n),
        .int64_mul_in_tvalid  (accept & sel_imul),
        .int64_mul_in1_tdata  (in1_iso_imul),
        .int64_mul_in2_tdata  (in2_iso_imul),
        .uint64_mult_in1      (imul_m1),
        .uint64_mult_in2      (imul_m2),
        .uint64_mult_result   (uint64_mult_result),
        .int64_mul_out_tvalid (),
        .int64_mul_out_tdata  (imul_out)
      );
      uint64_mul #(.DEBUG (DEBUG)) uint64_mul_inst (
        .clk (clk), .rst_n (rst_n),
        .uint64_mul_in_tvalid  (accept & sel_umul),
        .uint64_mul_in1_tdata  (in1_iso_umul),
        .uint64_mul_in2_tdata  (in2_iso_umul),
        .uint64_mult_in1       (umul_m1),
        .uint64_mult_in2       (umul_m2),
        .uint64_mult_result    (uint64_mult_result),
        .uint64_mul_out_tvalid (),
        .uint64_mul_out_tdata  (umul_out)
      );
    end else begin : gen_no_int_mul
      assign imul_out = 128'd0;
      assign umul_out = 128'd0;
      assign imul_m1  = 64'd0;
      assign imul_m2  = 64'd0;
      assign umul_m1  = 64'd0;
      assign umul_m2  = 64'd0;
    end

    if (DIVSQRT == 1) begin : gen_div_and_sqrt
      fpr_div #(.DEBUG (DEBUG), .BITS_PER_CYCLE (DIVSQRT_BITS_PER_CYCLE), .PIPELINED (DIVSQRT_PIPELINED)) fpr_div_inst (
        .clk (clk), .rst_n (rst_n),
        .fpr_div_in_tvalid  (accept & sel_div),
        .fpr_div_in_tready  (div_tready),
        .fpr_div_in1_tdata  ((in_op == `FPR_OP_INV) ? FPR_ONE : in1_iso_div),
        .fpr_div_in2_tdata  ((in_op == `FPR_OP_INV) ? in1_iso_div : in2_iso_div),
        .fpr_div_out_tvalid (),
        .fpr_div_out_tdata  (div_out)
      );
      fpr_sqrt #(.DEBUG (DEBUG), .BITS_PER_CYCLE (DIVSQRT_BITS_PER_CYCLE), .PIPELINED (DIVSQRT_PIPELINED)) fpr_sqrt_inst (
        .clk (clk), .rst_n (rst_n),
        .fpr_sqrt_in_tvalid  (accept & sel_sqrt),
        .fpr_sqrt_in_tready  (sqrt_tready),
        .fpr_sqrt_in_tdata   (in1_iso_sqrt),
        .fpr_sqrt_out_tvalid (),
        .fpr_sqrt_out_tdata  (sqrt_out)
      );
    end else if (DIVSQRT == 2) begin : gen_div_sqrt
      fpr_div_sqrt #(.DEBUG (DEBUG), .BITS_PER_CYCLE (DIVSQRT_BITS_PER_CYCLE), .PIPELINED (DIVSQRT_PIPELINED)) fpr_div_sqrt_inst (
        .clk (clk), .rst_n (rst_n),
        .fpr_div_sqrt_in_tvalid  (accept & sel_div),
        .fpr_div_sqrt_in_tready  (div_tready),
        .fpr_div_sqrt_op         (in_op == `FPR_OP_SQRT),
        .fpr_div_sqrt_in1_tdata  ((in_op == `FPR_OP_INV) ? FPR_ONE : in1_iso_div),
        .fpr_div_sqrt_in2_tdata  ((in_op == `FPR_OP_INV) ? in1_iso_div : in2_iso_div),
        .fpr_div_sqrt_out_tvalid (),
        .fpr_div_sqrt_out_tdata  (div_out)
      );
      assign sqrt_out    = 64'd0;
      assign sqrt_tready = 1'b0;
    end else begin : gen_no_div_sqrt
      assign div_out     = 64'd0;
      assign sqrt_out    = 64'd0;
      assign div_tready  = 1'b0;
      assign sqrt_tready = 1'b0;
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Output: the unit reserved for this cycle
  // ---------------------------------------------------------------------------
  reg  [63:0] out_d1, out_d2, out_d3;
  wire [3:0]  out_unit = slot_unit[0];

  always@ (*) begin
    out_d1 = 64'd0;
    out_d2 = 64'd0;
    out_d3 = 64'd0;
    case (out_unit)
      U_ADD:   out_d1 = add_out;
      U_MUL:   out_d1 = mul_out;
      U_FMA:   out_d1 = fma_out;
      U_TOINT: begin out_d1 = toint_int; out_d2 = toint_fpr; out_d3 = toint_res; end
      U_I2F:   out_d1 = i2f_out;
      U_DIV:   out_d1 = div_out;
      U_SQRT:  out_d1 = sqrt_out;
      U_IMUL:  begin out_d1 = imul_out[63:0]; out_d2 = imul_out[127:64]; end
      U_UMUL:  begin out_d1 = umul_out[63:0]; out_d2 = umul_out[127:64]; end
      default: ;
    endcase
  end

  assign out_tvalid = slot_busy[0];
  assign out_op     = slot_op[0];
  assign out_tuser  = slot_user[0];
  assign out_error  = slot_busy[0] & (out_unit == U_ERR);
  assign out_tdata  = slot_busy[0] ? out_d1 : 64'd0;
  assign out_tdata2 = slot_busy[0] ? out_d2 : 64'd0;
  assign out_tdata3 = slot_busy[0] ? out_d3 : 64'd0;

endmodule
