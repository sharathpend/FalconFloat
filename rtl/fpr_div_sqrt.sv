
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`include "defines.vh"

// Shared division / square root unit, round to nearest even (bit-exact with
// FALCON's fpr_div and fpr_sqrt; fpr_inv(x) is op = 0 with a = 1.0).
//   op = 0: a / b      op = 1: sqrt(a)   (b is ignored)
// One recurrence for both: per root/quotient bit, one compare + subtract.
//   div:  R >= D        ? R -= D        then R <<= 1
//   sqrt: R = (R << 2) | 2 new bits, then R >= {Q, 01} ? R -= {Q, 01}
// Same algorithms, parameters, latency and handshake as fpr_div and fpr_sqrt
// (see those files): BITS_PER_CYCLE = K bits per step (1..27), ITER = ceil(54 / K).
// PIPELINED = 0: iterative, latency ITER + 2, one new input every ITER + 1 cycles.
// PIPELINED = 1: one stage per step, latency ITER + 1, one input per cycle. The op
//                travels with each input, so divides and square roots can be mixed.
// Smaller than fpr_div + fpr_sqrt, but one operation at a time (iterative) and a
// slightly longer step (muxes, and the sqrt remainder is a few bits wider).
// Scope: as fpr_div (op = 0) and fpr_sqrt (op = 1).
module fpr_div_sqrt #(
  parameter DEBUG          = 0,
  parameter BITS_PER_CYCLE = 2,
  parameter PIPELINED      = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_div_sqrt_in_tvalid,
  output wire         fpr_div_sqrt_in_tready,
  input  wire         fpr_div_sqrt_op,         // 0 = a / b, 1 = sqrt(a)
  input  wire [63:0]  fpr_div_sqrt_in1_tdata,  // a
  input  wire [63:0]  fpr_div_sqrt_in2_tdata,  // b (op = 0 only)

  output wire         fpr_div_sqrt_out_tvalid,
  output wire [63:0]  fpr_div_sqrt_out_tdata
);

  localparam K    = BITS_PER_CYCLE;
  localparam QB   = 54;                // result bits needed: 53 + guard
  localparam ITER = (QB + K - 1) / K;
  localparam QT   = ITER * K;          // result bits produced, extra bits go to sticky
  localparam RW   = QT + 3;            // remainder width (sqrt needs the most)
  localparam CW   = $clog2(ITER + 1);
  localparam SW   = RW + QT + 54;      // step state: {R, Q, N}

  initial begin
    if (K < 1 || K > 27) begin
      $display("fpr_div_sqrt: BITS_PER_CYCLE must be 1..27");
      $finish;
    end
  end

  // K steps of the shared recurrence. n: sqrt input bits still to bring down.
  function [SW-1:0] ds_steps;
    input          is_sqrt;
    input [RW-1:0] r_in;
    input [QT-1:0] q_in;
    input [53:0]   n_in;
    input [52:0]   d;
    integer        j;
    reg   [RW-1:0] r;
    reg   [RW-1:0] sub;
    reg   [QT-1:0] q;
    reg   [53:0]   n;
    begin
      r = r_in;
      q = q_in;
      n = n_in;
      for (j = 0; j < K; j = j + 1) begin
        if (is_sqrt) r = {r[RW-3:0], n[53:52]};
        n   = {n[51:0], 2'b00};
        sub = is_sqrt ? {q, 2'b01} : d;
        if (r >= sub) begin
          r = r - sub;
          q = {q[QT-2:0], 1'b1};
        end else begin
          q = {q[QT-2:0], 1'b0};
        end
        if (!is_sqrt) r = r << 1;
      end
      ds_steps = {r, q, n};
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Input: unpack and align for the selected op
  // ---------------------------------------------------------------------------
  wire         a_sign, b_sign;
  wire [10:0]  a_exp,  b_exp;
  wire [51:0]  a_mant, b_mant;
  wire         a_lt_b;
  wire [RW-1:0] in_r;
  wire [53:0]  in_n;
  wire [52:0]  in_d;
  wire [10:0]  in_exp;
  wire         in_sign;
  wire         in_zero;
  wire         in_op;
  wire         accept;

  assign a_sign = fpr_div_sqrt_in1_tdata[63];
  assign a_exp  = fpr_div_sqrt_in1_tdata[62:52];
  assign a_mant = fpr_div_sqrt_in1_tdata[51:0];
  assign b_sign = fpr_div_sqrt_in2_tdata[63];
  assign b_exp  = fpr_div_sqrt_in2_tdata[62:52];
  assign b_mant = fpr_div_sqrt_in2_tdata[51:0];
  assign in_op  = fpr_div_sqrt_op;

  // div: R = 1.a (or 2 * 1.a when 1.a < 1.b), D = 1.b, exp = ea - eb + 1023 - a_lt_b
  // sqrt: R = 0, N = 1.m (odd exp) or 2 * 1.m (even exp), exp = (ea + 1022 + ea[0]) / 2
  assign a_lt_b  = (a_mant < b_mant);
  assign in_r    = in_op ? {RW{1'b0}} :
                   a_lt_b ? {{(RW-54){1'b0}}, 1'b1, a_mant, 1'b0} : {{(RW-53){1'b0}}, 1'b1, a_mant};
  assign in_n    = a_exp[0] ? {1'b0, 1'b1, a_mant} : {1'b1, a_mant, 1'b0};
  assign in_d    = {1'b1, b_mant};
  assign in_exp  = in_op ? (({1'b0, a_exp} + 12'd1022 + {11'd0, a_exp[0]}) >> 1) :
                           (a_exp - b_exp + 11'd1023 - {10'd0, a_lt_b});
  assign in_sign = in_op ? a_sign : (a_sign ^ b_sign);
  assign in_zero = (a_exp == 11'd0);

  // ---------------------------------------------------------------------------
  // Recurrence
  // ---------------------------------------------------------------------------
  wire          fin_valid;
  wire [QT-1:0] fin_q;
  wire [RW-1:0] fin_r;
  wire          fin_sign;
  wire [10:0]   fin_exp;
  wire          fin_zero;

  generate
    if (PIPELINED == 0) begin : gen_iterative
      `ifdef FPGA_DESIGN
        (* dont_touch = "true" *) reg          busy_reg = 0;
        (* dont_touch = "true" *) reg          fin_reg = 0;
        (* dont_touch = "true" *) reg [CW-1:0] cnt_reg = 0;
        (* dont_touch = "true" *) reg          op_reg = 0;
        (* dont_touch = "true" *) reg [RW-1:0] r_reg = 0;
        (* dont_touch = "true" *) reg [QT-1:0] q_reg = 0;
        (* dont_touch = "true" *) reg [53:0]   n_reg = 0;
        (* dont_touch = "true" *) reg [52:0]   d_reg = 0;
        (* dont_touch = "true" *) reg          sign_reg = 0;
        (* dont_touch = "true" *) reg [10:0]   exp_reg = 0;
        (* dont_touch = "true" *) reg          zero_reg = 0;
      `else
        (* dont_touch = "true" *) reg          busy_reg;
        (* dont_touch = "true" *) reg          fin_reg;
        (* dont_touch = "true" *) reg [CW-1:0] cnt_reg;
        (* dont_touch = "true" *) reg          op_reg;
        (* dont_touch = "true" *) reg [RW-1:0] r_reg;
        (* dont_touch = "true" *) reg [QT-1:0] q_reg;
        (* dont_touch = "true" *) reg [53:0]   n_reg;
        (* dont_touch = "true" *) reg [52:0]   d_reg;
        (* dont_touch = "true" *) reg          sign_reg;
        (* dont_touch = "true" *) reg [10:0]   exp_reg;
        (* dont_touch = "true" *) reg          zero_reg;
      `endif

      wire [SW-1:0] step;

      assign step                   = ds_steps(op_reg, r_reg, q_reg, n_reg, d_reg);
      assign fpr_div_sqrt_in_tready = ~busy_reg;
      assign accept                 = fpr_div_sqrt_in_tvalid & ~busy_reg;

      always@ (posedge clk) begin
        if (~rst_n) begin
          busy_reg <= 1'b0;
          fin_reg  <= 1'b0;
          cnt_reg  <= {CW{1'b0}};
        end else begin
          fin_reg <= 1'b0;
          if (accept) begin
            busy_reg <= 1'b1;
            cnt_reg  <= ITER;
          end else if (busy_reg) begin
            cnt_reg <= cnt_reg - 1'b1;
            if (cnt_reg == 1) begin
              busy_reg <= 1'b0;
              fin_reg  <= 1'b1;
            end
          end
        end

        if (accept) begin
          op_reg   <= in_op;
          r_reg    <= in_r;
          q_reg    <= {QT{1'b0}};
          n_reg    <= in_n;
          d_reg    <= in_d;
          sign_reg <= in_sign;
          exp_reg  <= in_exp;
          zero_reg <= in_zero;
        end else if (busy_reg) begin
          {r_reg, q_reg, n_reg} <= step;
        end
      end

      assign fin_valid = fin_reg;
      assign fin_q     = q_reg;
      assign fin_r     = r_reg;
      assign fin_sign  = sign_reg;
      assign fin_exp   = exp_reg;
      assign fin_zero  = zero_reg;
    end else begin : gen_pipelined
      reg  [RW-1:0]   st_r    [0:ITER-1];
      reg  [QT-1:0]   st_q    [0:ITER-1];
      reg  [53:0]     st_n    [0:ITER-1];
      reg  [52:0]     st_d    [0:ITER-1];
      reg             st_op   [0:ITER-1];
      reg             st_sign [0:ITER-1];
      reg  [10:0]     st_exp  [0:ITER-1];
      reg             st_zero [0:ITER-1];
      reg  [ITER-1:0] st_valid;
      wire [SW-1:0]   step    [0:ITER-1];
      integer         s;

      assign fpr_div_sqrt_in_tready = 1'b1;
      assign accept                 = fpr_div_sqrt_in_tvalid;

      genvar g;
      for (g = 0; g < ITER; g = g + 1) begin : gen_step
        if (g == 0) begin : gen_first
          assign step[g] = ds_steps(in_op, in_r, {QT{1'b0}}, in_n, in_d);
        end else begin : gen_next
          assign step[g] = ds_steps(st_op[g-1], st_r[g-1], st_q[g-1], st_n[g-1], st_d[g-1]);
        end
      end

      `ifdef FPGA_DESIGN
        initial begin
          st_valid = {ITER{1'b0}};
          for (s = 0; s < ITER; s = s + 1) begin
            st_r[s] = {RW{1'b0}}; st_q[s] = {QT{1'b0}}; st_n[s] = 54'd0; st_d[s] = 53'd0;
            st_op[s] = 1'b0; st_sign[s] = 1'b0; st_exp[s] = 11'd0; st_zero[s] = 1'b0;
          end
        end
      `endif

      always@ (posedge clk) begin
        if (~rst_n) begin
          st_valid <= {ITER{1'b0}};
        end else begin
          st_valid <= {st_valid[ITER-2:0], accept};
        end

        {st_r[0], st_q[0], st_n[0]} <= step[0];
        st_d[0]    <= in_d;
        st_op[0]   <= in_op;
        st_sign[0] <= in_sign;
        st_exp[0]  <= in_exp;
        st_zero[0] <= in_zero;
        for (s = 1; s < ITER; s = s + 1) begin
          {st_r[s], st_q[s], st_n[s]} <= step[s];
          st_d[s]    <= st_d[s-1];
          st_op[s]   <= st_op[s-1];
          st_sign[s] <= st_sign[s-1];
          st_exp[s]  <= st_exp[s-1];
          st_zero[s] <= st_zero[s-1];
        end
      end

      assign fin_valid = st_valid[ITER-1];
      assign fin_q     = st_q[ITER-1];
      assign fin_r     = st_r[ITER-1];
      assign fin_sign  = st_sign[ITER-1];
      assign fin_exp   = st_exp[ITER-1];
      assign fin_zero  = st_zero[ITER-1];
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Round (RNE) and pack, shared
  // ---------------------------------------------------------------------------
  wire [QT:0]  q_ext;                // fin_q with one extra 0 bit, so the sticky range is never empty
  wire [51:0]  mant_truncated;
  wire         guard_bit;
  wire         sticky_bit;
  wire         round_up;
  wire [52:0]  mant_rounded;         // bit 52 = carry out of rounding
  wire [10:0]  out_exp;
  wire [63:0]  out_tdata;

  assign q_ext          = {fin_q, 1'b0};              // q_ext[QT] is the integer bit (always 1)
  assign mant_truncated = q_ext[QT-1 -: 52];
  assign guard_bit      = q_ext[QT-53];
  assign sticky_bit     = (|q_ext[QT-54:0]) | (|fin_r);
  assign round_up       = guard_bit & (sticky_bit | mant_truncated[0]);
  assign mant_rounded   = {1'b0, mant_truncated} + {52'd0, round_up};
  assign out_exp        = fin_exp + {10'd0, mant_rounded[52]};

  assign out_tdata = fin_zero ? {fin_sign, 63'd0} : {fin_sign, out_exp, mant_rounded[51:0]};

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         fpr_div_sqrt_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_div_sqrt_out_tdata_reg = 0;
  `else
    (* dont_touch = "true" *) reg         fpr_div_sqrt_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_div_sqrt_out_tdata_reg;
  `endif

  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_div_sqrt_out_tvalid_reg <= 1'b0;
      fpr_div_sqrt_out_tdata_reg  <= 64'd0;
    end else begin
      fpr_div_sqrt_out_tvalid_reg <= fin_valid;
      if (fin_valid) fpr_div_sqrt_out_tdata_reg <= out_tdata;
    end
  end

  assign fpr_div_sqrt_out_tvalid = fpr_div_sqrt_out_tvalid_reg;
  assign fpr_div_sqrt_out_tdata  = fpr_div_sqrt_out_tdata_reg;

endmodule
