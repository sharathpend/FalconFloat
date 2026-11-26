
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`include "defines.vh"

// Double square root, round to nearest even (bit-exact with FALCON's fpr_sqrt).
// Restoring digit-by-digit square root on the significand, no multipliers:
//   x = 1.m * 2^e. For odd e the significand is doubled (and e decremented), so
//   s = 1.m or 2 * 1.m is in [1, 4) and sqrt(s) is in [1, 2). The integer root of
//   N = s * 2^106 gives 54 root bits (53 + guard). Each step brings down 2 bits of N:
//     R = (R << 2) | next 2 bits;  T = (Q << 2) | 1
//     R >= T ? (R = R - T, Q = (Q << 1) | 1) : (Q = Q << 1)
//   sticky = remainder != 0.
// BITS_PER_CYCLE = K root bits per step (1..27), ITER = ceil(54 / K) steps.
// PIPELINED = 0: iterative, one unit. Latency ITER + 2 cycles, one new input every
//                ITER + 1 cycles (in_tready low while busy).
// PIPELINED = 1: one register stage per step. Latency ITER + 1 cycles, one input
//                per cycle (in_tready always 1).
// Same parameters and handshake as fpr_div. An input is accepted when
// in_tvalid & in_tready.
// Scope (matches FALCON's needs): x is +/-0 or a positive normal number (the result
// is then always normal). sqrt(+/-0) = +/-0. Negative inputs are not handled. An
// exponent of 0 is treated as zero. Output data only updates when out_tvalid is set.
module fpr_sqrt #(
  parameter DEBUG          = 0,
  parameter BITS_PER_CYCLE = 2,
  parameter PIPELINED      = 0
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_sqrt_in_tvalid,
  output wire         fpr_sqrt_in_tready,
  input  wire [63:0]  fpr_sqrt_in_tdata,

  output wire         fpr_sqrt_out_tvalid,
  output wire [63:0]  fpr_sqrt_out_tdata
);

  localparam K    = BITS_PER_CYCLE;
  localparam QB   = 54;                // root bits needed: 53 + guard
  localparam ITER = (QB + K - 1) / K;
  localparam QT   = ITER * K;          // root bits produced, extra bits go to sticky
  localparam RW   = QT + 3;            // remainder width: R <= 2Q, plus 2 new bits
  localparam CW   = $clog2(ITER + 1);

  initial begin
    if (K < 1 || K > 27) begin
      $display("fpr_sqrt: BITS_PER_CYCLE must be 1..27");
      $finish;
    end
  end

  // K restoring steps. n holds the bits of N still to bring down, top 2 bits first.
  function [RW+QT+54-1:0] sqrt_steps;
    input [RW-1:0] r_in;
    input [QT-1:0] q_in;
    input [53:0]   n_in;
    integer        j;
    reg   [RW-1:0] r;
    reg   [RW-1:0] t;
    reg   [QT-1:0] q;
    reg   [53:0]   n;
    begin
      r = r_in;
      q = q_in;
      n = n_in;
      for (j = 0; j < K; j = j + 1) begin
        r = {r[RW-3:0], n[53:52]};
        n = {n[51:0], 2'b00};
        t = {q, 2'b01};
        if (r >= t) begin
          r = r - t;
          q = {q[QT-2:0], 1'b1};
        end else begin
          q = {q[QT-2:0], 1'b0};
        end
      end
      sqrt_steps = {r, q, n};
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Input: unpack and align
  // ---------------------------------------------------------------------------
  wire         x_sign;
  wire [10:0]  x_exp;
  wire [51:0]  x_mant;
  wire [53:0]  in_n;                 // s * 2^52: {0, 1.m} for odd exp, {1.m, 0} for even exp
  wire [10:0]  in_exp;
  wire         in_sign;
  wire         in_zero;
  wire         accept;

  assign x_sign = fpr_sqrt_in_tdata[63];
  assign x_exp  = fpr_sqrt_in_tdata[62:52];
  assign x_mant = fpr_sqrt_in_tdata[51:0];

  // Biased exp odd  -> unbiased even: s = 1.m,     result exp = (exp + 1023) / 2
  // Biased exp even -> unbiased odd:  s = 2 * 1.m, result exp = (exp + 1022) / 2
  assign in_n    = x_exp[0] ? {1'b0, 1'b1, x_mant} : {1'b1, x_mant, 1'b0};
  assign in_exp  = ({1'b0, x_exp} + 12'd1022 + {11'd0, x_exp[0]}) >> 1;
  assign in_sign = x_sign;
  assign in_zero = (x_exp == 11'd0);

  // ---------------------------------------------------------------------------
  // Recurrence
  // ---------------------------------------------------------------------------
  wire          fin_valid;           // final root ready this cycle
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
        (* dont_touch = "true" *) reg [RW-1:0] r_reg = 0;
        (* dont_touch = "true" *) reg [QT-1:0] q_reg = 0;
        (* dont_touch = "true" *) reg [53:0]   n_reg = 0;
        (* dont_touch = "true" *) reg          sign_reg = 0;
        (* dont_touch = "true" *) reg [10:0]   exp_reg = 0;
        (* dont_touch = "true" *) reg          zero_reg = 0;
      `else
        (* dont_touch = "true" *) reg          busy_reg;
        (* dont_touch = "true" *) reg          fin_reg;
        (* dont_touch = "true" *) reg [CW-1:0] cnt_reg;
        (* dont_touch = "true" *) reg [RW-1:0] r_reg;
        (* dont_touch = "true" *) reg [QT-1:0] q_reg;
        (* dont_touch = "true" *) reg [53:0]   n_reg;
        (* dont_touch = "true" *) reg          sign_reg;
        (* dont_touch = "true" *) reg [10:0]   exp_reg;
        (* dont_touch = "true" *) reg          zero_reg;
      `endif

      wire [RW+QT+54-1:0] step;

      assign step               = sqrt_steps(r_reg, q_reg, n_reg);
      assign fpr_sqrt_in_tready = ~busy_reg;
      assign accept             = fpr_sqrt_in_tvalid & ~busy_reg;

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
          r_reg    <= {RW{1'b0}};
          q_reg    <= {QT{1'b0}};
          n_reg    <= in_n;
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
      reg  [RW-1:0]       st_r    [0:ITER-1];
      reg  [QT-1:0]       st_q    [0:ITER-1];
      reg  [53:0]         st_n    [0:ITER-1];
      reg                 st_sign [0:ITER-1];
      reg  [10:0]         st_exp  [0:ITER-1];
      reg                 st_zero [0:ITER-1];
      reg  [ITER-1:0]     st_valid;
      wire [RW+QT+54-1:0] step    [0:ITER-1];
      integer             s;

      assign fpr_sqrt_in_tready = 1'b1;
      assign accept             = fpr_sqrt_in_tvalid;

      genvar g;
      for (g = 0; g < ITER; g = g + 1) begin : gen_step
        if (g == 0) begin : gen_first
          assign step[g] = sqrt_steps({RW{1'b0}}, {QT{1'b0}}, in_n);
        end else begin : gen_next
          assign step[g] = sqrt_steps(st_r[g-1], st_q[g-1], st_n[g-1]);
        end
      end

      `ifdef FPGA_DESIGN
        initial begin
          st_valid = {ITER{1'b0}};
          for (s = 0; s < ITER; s = s + 1) begin
            st_r[s] = {RW{1'b0}}; st_q[s] = {QT{1'b0}}; st_n[s] = 54'd0;
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

        {st_r[0], st_q[0], st_n[0]} <= step[0];
        st_sign[0] <= in_sign;
        st_exp[0]  <= in_exp;
        st_zero[0] <= in_zero;
        for (s = 1; s < ITER; s = s + 1) begin
          {st_r[s], st_q[s], st_n[s]} <= step[s];
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

  assign out_tdata = fin_zero ? {fin_sign, 63'd0} : {1'b0, out_exp, mant_rounded[51:0]};

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg         fpr_sqrt_out_tvalid_reg = 0;
    (* dont_touch = "true" *) reg  [63:0] fpr_sqrt_out_tdata_reg = 0;
  `else
    (* dont_touch = "true" *) reg         fpr_sqrt_out_tvalid_reg;
    (* dont_touch = "true" *) reg  [63:0] fpr_sqrt_out_tdata_reg;
  `endif

  always@ (posedge clk) begin
    if (~rst_n) begin
      fpr_sqrt_out_tvalid_reg <= 1'b0;
      fpr_sqrt_out_tdata_reg  <= 64'd0;
    end else begin
      fpr_sqrt_out_tvalid_reg <= fin_valid;
      if (fin_valid) fpr_sqrt_out_tdata_reg <= out_tdata;
    end
  end

  assign fpr_sqrt_out_tvalid = fpr_sqrt_out_tvalid_reg;
  assign fpr_sqrt_out_tdata  = fpr_sqrt_out_tdata_reg;

endmodule
