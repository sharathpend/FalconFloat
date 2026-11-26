
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`include "defines.vh"

// FFT butterfly on complex doubles, as in FALCON's FFT / iFFT (fft.c):
//   mode = 0 (forward, FFT):   t = y * s;   x' = x + t;   y' = x - t
//   mode = 1 (inverse, iFFT):  x' = x + y;  y' = (x - y) * s
//   conj_s = 1 uses conj(s) (the iFFT twiddles are the conjugated FFT ones).
// Complex multiply, matching FPC_MUL:
//   re = fpr_sub(fpr_mul(a_re, s_re), fpr_mul(a_im, s_im))
//   im = fpr_add(fpr_mul(a_re, s_im), fpr_mul(a_im, s_re))
// done as one fpr_mul plus one fpr_fma per component.
//
// FUSED = 0: bit-exact with FALCON's reference code.
// FUSED = 1: each fpr_fma rounds a * b + c once (one rounding less per component).
// REG_STAGES = 1 or 2, passed to fpr_fma. Latency is REG_STAGES + 2 cycles in both
//   modes, one butterfly per cycle.
// The forward pipeline is MUL -> FMA -> ADD and the inverse is ADD -> MUL -> FMA, so
// the 4 adders are shared between the two modes. The mode can only change when the
// pipeline is empty: in_tready drops while a butterfly of the other mode is in flight.
// An input is accepted when in_tvalid & in_tready.
// Multiplies use uint_mul_core (implementation chosen in defines.vh).
module fpr_butterfly #(
  parameter DEBUG      = 0,
  parameter FUSED      = 0,
  parameter REG_STAGES = 1
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         fpr_butterfly_in_tvalid,
  output wire         fpr_butterfly_in_tready,
  input  wire         fpr_butterfly_in_mode,   // 0 = forward, 1 = inverse
  input  wire         fpr_butterfly_in_conj_s, // 1 = use conj(s)
  input  wire [63:0]  fpr_butterfly_in_x_re,
  input  wire [63:0]  fpr_butterfly_in_x_im,
  input  wire [63:0]  fpr_butterfly_in_y_re,
  input  wire [63:0]  fpr_butterfly_in_y_im,
  input  wire [63:0]  fpr_butterfly_in_s_re,
  input  wire [63:0]  fpr_butterfly_in_s_im,

  output wire         fpr_butterfly_out_tvalid,
  output wire [63:0]  fpr_butterfly_out_x_re,
  output wire [63:0]  fpr_butterfly_out_x_im,
  output wire [63:0]  fpr_butterfly_out_y_re,
  output wire [63:0]  fpr_butterfly_out_y_im
);

  localparam LAT = REG_STAGES + 2; // input sampled -> output register loaded, in clock edges

  // ---------------------------------------------------------------------------
  // Control
  // ---------------------------------------------------------------------------
  wire          accept;
  wire          pipe_empty;
  wire          mode;                 // mode of the butterflies in flight (or of the next one)
  wire [63:0]   s_im_in;              // conj applied

  `ifdef FPGA_DESIGN
    (* dont_touch = "true" *) reg  [LAT-1:0] valid_sr = 0;    // valid_sr[k]: loaded k edges after the input
    (* dont_touch = "true" *) reg            cur_mode_reg = 0;
    (* dont_touch = "true" *) reg  [63:0]    s_re_d1_reg = 0; // inverse: s waits for x - y
    (* dont_touch = "true" *) reg  [63:0]    s_im_d1_reg = 0;
    (* dont_touch = "true" *) reg  [63:0]    p_re_d1_reg = 0; // FMA operands, one cycle after the MUL stage
    (* dont_touch = "true" *) reg  [63:0]    p_im_d1_reg = 0;
    (* dont_touch = "true" *) reg  [63:0]    s_re_fma_reg = 0;
  `else
    (* dont_touch = "true" *) reg  [LAT-1:0] valid_sr;
    (* dont_touch = "true" *) reg            cur_mode_reg;
    (* dont_touch = "true" *) reg  [63:0]    s_re_d1_reg;
    (* dont_touch = "true" *) reg  [63:0]    s_im_d1_reg;
    (* dont_touch = "true" *) reg  [63:0]    p_re_d1_reg;
    (* dont_touch = "true" *) reg  [63:0]    p_im_d1_reg;
    (* dont_touch = "true" *) reg  [63:0]    s_re_fma_reg;
  `endif

  assign pipe_empty              = ~|valid_sr;
  assign mode                    = pipe_empty ? fpr_butterfly_in_mode : cur_mode_reg;
  assign fpr_butterfly_in_tready = pipe_empty | (fpr_butterfly_in_mode == cur_mode_reg);
  assign accept                  = fpr_butterfly_in_tvalid & fpr_butterfly_in_tready;
  assign s_im_in                 = {fpr_butterfly_in_s_im[63] ^ fpr_butterfly_in_conj_s, fpr_butterfly_in_s_im[62:0]};

  // ---------------------------------------------------------------------------
  // Shared adders: forward x_d + t, x_d - t;  inverse x + y, x - y
  // ---------------------------------------------------------------------------
  wire [63:0]  add_a_re, add_a_im, add_b_re, add_b_im;
  wire [63:0]  sum_re, sum_im, diff_re, diff_im; // registered inside fpr_add

  wire [63:0]  x_dly_re, x_dly_im;               // delay line outputs
  wire [63:0]  t_re, t_im;                       // FMA outputs

  assign add_a_re = mode ? fpr_butterfly_in_x_re : x_dly_re;
  assign add_a_im = mode ? fpr_butterfly_in_x_im : x_dly_im;
  assign add_b_re = mode ? fpr_butterfly_in_y_re : t_re;
  assign add_b_im = mode ? fpr_butterfly_in_y_im : t_im;

  fpr_add #(.DEBUG (DEBUG)) fpr_add_sum_re (
    .clk (clk), .rst_n (rst_n), .fpr_add_in_tvalid (1'b1),
    .fpr_add_in1_tdata (add_a_re), .fpr_add_in2_tdata (add_b_re),
    .fpr_add_out_tvalid (), .fpr_add_out_tdata (sum_re)
  );
  fpr_add #(.DEBUG (DEBUG)) fpr_add_sum_im (
    .clk (clk), .rst_n (rst_n), .fpr_add_in_tvalid (1'b1),
    .fpr_add_in1_tdata (add_a_im), .fpr_add_in2_tdata (add_b_im),
    .fpr_add_out_tvalid (), .fpr_add_out_tdata (sum_im)
  );
  fpr_add #(.DEBUG (DEBUG)) fpr_add_diff_re (
    .clk (clk), .rst_n (rst_n), .fpr_add_in_tvalid (1'b1),
    .fpr_add_in1_tdata (add_a_re), .fpr_add_in2_tdata ({~add_b_re[63], add_b_re[62:0]}),
    .fpr_add_out_tvalid (), .fpr_add_out_tdata (diff_re)
  );
  fpr_add #(.DEBUG (DEBUG)) fpr_add_diff_im (
    .clk (clk), .rst_n (rst_n), .fpr_add_in_tvalid (1'b1),
    .fpr_add_in1_tdata (add_a_im), .fpr_add_in2_tdata ({~add_b_im[63], add_b_im[62:0]}),
    .fpr_add_out_tvalid (), .fpr_add_out_tdata (diff_im)
  );

  // ---------------------------------------------------------------------------
  // Complex multiply p * s: MUL stage (2 x fpr_mul), then FMA stage (2 x fpr_fma)
  //   forward: p = y (input), s = input      inverse: p = x - y (adders), s = delayed
  // ---------------------------------------------------------------------------
  wire [63:0]  p_re, p_im, mul_s_re, mul_s_im;
  wire [63:0]  m_im_s_im;                        // p_im * s_im
  wire [63:0]  m_re_s_im;                        // p_re * s_im
  wire         fma_in_tvalid;

  assign p_re     = mode ? diff_re     : fpr_butterfly_in_y_re;
  assign p_im     = mode ? diff_im     : fpr_butterfly_in_y_im;
  assign mul_s_re = mode ? s_re_d1_reg : fpr_butterfly_in_s_re;
  assign mul_s_im = mode ? s_im_d1_reg : s_im_in;

  fpr_mul #(.DEBUG (DEBUG), .INTERNAL_MULT (1)) fpr_mul_im_s_im (
    .clk (clk), .rst_n (rst_n), .fpr_mul_in_tvalid (1'b1),
    .fpr_mul_in1_tdata (p_im), .fpr_mul_in2_tdata (mul_s_im),
    .uint64_mult_in1 (), .uint64_mult_in2 (), .uint64_mult_result (128'd0),
    .fpr_mul_out_tvalid (), .fpr_mul_out_tdata (m_im_s_im)
  );
  fpr_mul #(.DEBUG (DEBUG), .INTERNAL_MULT (1)) fpr_mul_re_s_im (
    .clk (clk), .rst_n (rst_n), .fpr_mul_in_tvalid (1'b1),
    .fpr_mul_in1_tdata (p_re), .fpr_mul_in2_tdata (mul_s_im),
    .uint64_mult_in1 (), .uint64_mult_in2 (), .uint64_mult_result (128'd0),
    .fpr_mul_out_tvalid (), .fpr_mul_out_tdata (m_re_s_im)
  );

  // FMA input valid = MUL stage input valid, one cycle later
  assign fma_in_tvalid = mode ? valid_sr[1] : valid_sr[0];

  // re = p_re * s_re - p_im * s_im
  fpr_fma #(.DEBUG (DEBUG), .FUSED (FUSED), .REG_STAGES (REG_STAGES), .INTERNAL_MULT (1)) fpr_fma_re (
    .clk (clk), .rst_n (rst_n), .fpr_fma_in_tvalid (fma_in_tvalid),
    .fpr_fma_in1_tdata (p_re_d1_reg), .fpr_fma_in2_tdata (s_re_fma_reg), .fpr_fma_in3_tdata (m_im_s_im),
    .fpr_fma_op (2'b01),
    .uint64_mult_in1 (), .uint64_mult_in2 (), .uint64_mult_result (128'd0),
    .fpr_fma_out_tvalid (), .fpr_fma_out_tdata (t_re)
  );
  // im = p_im * s_re + p_re * s_im
  fpr_fma #(.DEBUG (DEBUG), .FUSED (FUSED), .REG_STAGES (REG_STAGES), .INTERNAL_MULT (1)) fpr_fma_im (
    .clk (clk), .rst_n (rst_n), .fpr_fma_in_tvalid (fma_in_tvalid),
    .fpr_fma_in1_tdata (p_im_d1_reg), .fpr_fma_in2_tdata (s_re_fma_reg), .fpr_fma_in3_tdata (m_re_s_im),
    .fpr_fma_op (2'b00),
    .uint64_mult_in1 (), .uint64_mult_in2 (), .uint64_mult_result (128'd0),
    .fpr_fma_out_tvalid (), .fpr_fma_out_tdata (t_im)
  );

  // ---------------------------------------------------------------------------
  // Delay line, REG_STAGES + 1 deep
  //   forward: x from the input, read by the adders together with t
  //   inverse: x + y from the adders, read by the output together with the product
  // ---------------------------------------------------------------------------
  wire [127:0] dly_in;
  reg  [127:0] dly [0:REG_STAGES];
  integer      d;

  assign dly_in   = mode ? {sum_re, sum_im} : {fpr_butterfly_in_x_re, fpr_butterfly_in_x_im};
  assign x_dly_re = dly[REG_STAGES][127:64];
  assign x_dly_im = dly[REG_STAGES][63:0];

  `ifdef FPGA_DESIGN
    initial for (d = 0; d <= REG_STAGES; d = d + 1) dly[d] = 128'd0;
  `endif

  always@ (posedge clk) begin
    if (~rst_n) begin
      valid_sr     <= {LAT{1'b0}};
      cur_mode_reg <= 1'b0;
    end else begin
      valid_sr     <= {valid_sr[LAT-2:0], accept};
      if (accept) cur_mode_reg <= mode;
    end
    s_re_d1_reg  <= fpr_butterfly_in_s_re;
    s_im_d1_reg  <= s_im_in;
    p_re_d1_reg  <= p_re;
    p_im_d1_reg  <= p_im;
    s_re_fma_reg <= mul_s_re;
    dly[0]       <= dly_in;
    for (d = 1; d <= REG_STAGES; d = d + 1) dly[d] <= dly[d-1];
  end

  // ---------------------------------------------------------------------------
  // Outputs (all loaded REG_STAGES + 2 edges after the input)
  // ---------------------------------------------------------------------------
  assign fpr_butterfly_out_tvalid = valid_sr[LAT-1];
  assign fpr_butterfly_out_x_re   = cur_mode_reg ? x_dly_re : sum_re;
  assign fpr_butterfly_out_x_im   = cur_mode_reg ? x_dly_im : sum_im;
  assign fpr_butterfly_out_y_re   = cur_mode_reg ? t_re     : diff_re;
  assign fpr_butterfly_out_y_im   = cur_mode_reg ? t_im     : diff_im;

endmodule
