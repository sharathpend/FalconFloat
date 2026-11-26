
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`include "defines.vh"

// Double division a / b, round to nearest even (bit-exact with FALCON's fpr_div).
// Radix-2 restoring digit recurrence on the significands, no multipliers:
//   a' = 1.a (or 2 * 1.a when 1.a < 1.b), so that q = a' / 1.b is in [1, 2)
//   each step: q_bit = (R >= D), R = (R - q_bit * D) << 1
//   54 quotient bits (53 + guard) are needed, sticky = remainder != 0.
// BITS_PER_CYCLE = K quotient bits per step (1..27), ITER = ceil(54 / K) steps.
// PIPELINED = 0: iterative, one divider. Latency ITER + 2 cycles, one new input
//                every ITER + 1 cycles (in_tready low while busy).
// PIPELINED = 1: one register stage per step. Latency ITER + 1 cycles, one input
//                per cycle (in_tready always 1).
// An input is accepted when in_tvalid & in_tready.
// Scope (matches FALCON's needs): a is zero or normal, b is normal, the result is
// zero or normal. Division by zero is not handled. An exponent of 0 on a is treated
// as zero. Output data only updates when out_tvalid is set.
module fpr_div #(
  parameter DEBUG          = 0,
  parameter BITS_PER_CYCLE = 2,
  parameter PIPELINED      = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_div_in_tvalid,
  output wire         fpr_div_in_tready,
  input  wire [63:0]  fpr_div_in1_tdata,  // a (dividend)
  input  wire [63:0]  fpr_div_in2_tdata,  // b (divisor)

  output wire         fpr_div_out_tvalid,
  output wire [63:0]  fpr_div_out_tdata
);

  localparam K    = BITS_PER_CYCLE;
  localparam QB   = 54;                // quotient bits needed: 53 + guard
  localparam ITER = (QB + K - 1) / K;
  localparam QT   = ITER * K;          // quotient bits produced, extra bits go to sticky
  localparam CW   = $clog2(ITER + 1);

  initial begin
    if (K < 1 || K > 27) begin
      $display("fpr_div: BITS_PER_CYCLE must be 1..27");
      $finish;
    end
  end

  // K restoring steps. R < 2D always holds, so 55 bits are enough.
  function [55+K-1:0] div_steps;
    input [54:0] r_in;
    input [52:0] d;
    integer      j;
    reg   [54:0] r;
    reg   [K-1:0] q;
    begin
      r = r_in;
      for (j = K - 1; j >= 0; j = j - 1) begin
        if (r >= {2'b00, d}) begin
          q[j] = 1'b1;
          r    = r - {2'b00, d};
        end else begin
          q[j] = 1'b0;
        end
        r = r << 1;
      end
      div_steps = {r, q};
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Input: unpack and align
  // ---------------------------------------------------------------------------
  wire         a_sign, b_sign;
  wire [10:0]  a_exp,  b_exp;
  wire [51:0]  a_mant, b_mant;
  wire         a_lt_b;               // 1.a < 1.b
  wire [54:0]  in_r;                 // a' = 1.a or 2 * 1.a
  wire [52:0]  in_d;                 // 1.b
  wire         in_sign;
  wire [10:0]  in_exp;               // biased result exponent before rounding
  wire         in_zero;
  wire         accept;

  assign a_sign = fpr_div_in1_tdata[63];
  assign a_exp  = fpr_div_in1_tdata[62:52];
  assign a_mant = fpr_div_in1_tdata[51:0];
  assign b_sign = fpr_div_in2_tdata[63];
  assign b_exp  = fpr_div_in2_tdata[62:52];
  assign b_mant = fpr_div_in2_tdata[51:0];

  assign a_lt_b  = (a_mant < b_mant);
  assign in_r    = a_lt_b ? {1'b0, 1'b1, a_mant, 1'b0} : {2'b00, 1'b1, a_mant};
  assign in_d    = {1'b1, b_mant};
  assign in_sign = a_sign ^ b_sign;
  // ea - eb + 1023 - a_lt_b, 11-bit (mod 2048) arithmetic is exact for in-scope results
  assign in_exp  = a_exp - b_exp + 11'd1023 - {10'd0, a_lt_b};
  assign in_zero = (a_exp == 11'd0);

  // ---------------------------------------------------------------------------
  // Recurrence
  // ---------------------------------------------------------------------------
  wire          fin_valid;           // final quotient ready this cycle
  wire [QT-1:0] fin_q;
  wire [54:0]   fin_r;
  wire          fin_sign;
  wire [10:0]   fin_exp;
  wire          fin_zero;

  generate
    if (PIPELINED == 0) begin : gen_iterative
      `ifdef FPGA_DESIGN
        (* dont_touch = "true" *) reg          busy_reg = 0;
        (* dont_touch = "true" *) reg          fin_reg = 0;
        (* dont_touch = "true" *) reg [CW-1:0] cnt_reg = 0;
        (* dont_touch = "true" *) reg [54:0]   r_reg = 0;
        (* dont_touch = "true" *) reg [52:0]   d_reg = 0;
        (* dont_touch = "true" *) reg [QT-1:0] q_reg = 0;
        (* dont_touch = "true" *) reg          sign_reg = 0;
        (* dont_touch = "true" *) reg [10:0]   exp_reg = 0;
        (* dont_touch = "true" *) reg          zero_reg = 0;
      `else
        (* dont_touch = "true" *) reg          busy_reg;
        (* dont_touch = "true" *) reg          fin_reg;
        (* dont_touch = "true" *) reg [CW-1:0] cnt_reg;
        (* dont_touch = "true" *) reg [54:0]   r_reg;
        (* dont_touch = "true" *) reg [52:0]   d_reg;
        (* dont_touch = "true" *) reg [QT-1:0] q_reg;
        (* dont_touch = "true" *) reg          sign_reg;
        (* dont_touch = "true" *) reg [10:0]   exp_reg;
        (* dont_touch = "true" *) reg          zero_reg;
      `endif

      wire [55+K-1:0] step;

      assign step              = div_steps(r_reg, d_reg);
      assign fpr_div_in_tready = ~busy_reg;
      assign accept            = fpr_div_in_tvalid & ~busy_reg;

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
          r_reg    <= in_r;
          d_reg    <= in_d;
          q_reg    <= {QT{1'b0}};
          sign_reg <= in_sign;
          exp_reg  <= in_exp;
          zero_reg <= in_zero;
        end else if (busy_reg) begin
          r_reg <= step[55+K-1:K];
          q_reg <= {q_reg[QT-K-1:0], step[K-1:0]};
        end
      end

      assign fin_valid = fin_reg;
      assign fin_q     = q_reg;
      assign fin_r     = r_reg;
      assign fin_sign  = sign_reg;
      assign fin_exp   = exp_reg;
      assign fin_zero  = zero_reg;
    end else begin : gen_pipelined
      reg  [54:0]     st_r    [0:ITER-1];
      reg  [52:0]     st_d    [0:ITER-1];
      reg  [QT-1:0]   st_q    [0:ITER-1];
      reg             st_sign [0:ITER-1];
      reg  [10:0]     st_exp  [0:ITER-1];
      reg             st_zero [0:ITER-1];
      reg  [ITER-1:0] st_valid;
      wire [55+K-1:0] step    [0:ITER-1];
      integer         s;

      assign fpr_div_in_tready = 1'b1;
      assign accept            = fpr_div_in_tvalid;

      genvar g;
      for (g = 0; g < ITER; g = g + 1) begin : gen_step
        if (g == 0) begin : gen_first
          assign step[g] = div_steps(in_r, in_d);
        end else begin : gen_next
          assign step[g] = div_steps(st_r[g-1], st_d[g-1]);
        end
      end

      `ifdef FPGA_DESIGN
        initial begin
          st_valid = {ITER{1'b0}};
          for (s = 0; s < ITER; s = s + 1) begin
            st_r[s] = 55'd0; st_d[s] = 53'd0; st_q[s] = {QT{1'b0}};
            st_sign[s] = 1'b0; st_exp[s] = 11'd0; st_zero[s] = 1'b0;
          end
        end
      `endif

      always@ (posedge clk) begin
        if (~rst_n) begin
          st_valid <= {ITER{1'b0}};
        end else begin
          st_valid <= {st_valid[ITER-2:0], accept};
        end

        st_r[0]    <= step[0][55+K-1:K];
        st_d[0]    <= in_d;
        st_q[0]    <= {{(QT-K){1'b0}}, step[0][K-1:0]};
        st_sign[0] <= in_sign;
        st_exp[0]  <= in_exp;
        st_zero[0] <= in_zero;
        for (s = 1; s < ITER; s = s + 1) begin
          st_r[s]    <= step[s][55+K-1:K];
          st_d[s]    <= st_d[s-1];
          st_q[s]    <= {st_q[s-1][QT-K-1:0], step[s][K-1:0]};
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
  // Round (RNE) and pack
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
    (* dont_touch = "true" *) reg         fpr_div_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_div_out_tdata_reg = 0;
  `else
    (* dont_touch = "true" *) reg         fpr_div_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_div_out_tdata_reg;
  `endif

  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_div_out_tvalid_reg <= 1'b0;
      fpr_div_out_tdata_reg  <= 64'd0;
    end else begin
      fpr_div_out_tvalid_reg <= fin_valid;
      if (fin_valid) fpr_div_out_tdata_reg <= out_tdata;
    end
  end

  assign fpr_div_out_tvalid = fpr_div_out_tvalid_reg;
  assign fpr_div_out_tdata  = fpr_div_out_tdata_reg;

endmodule
