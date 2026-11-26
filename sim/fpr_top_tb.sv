
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`timescale 1ns/1ps

// Self-checking testbench for fpr_top. Streams a random mix of ops with random idle
// cycles, honors in_tready, and matches each result by out_tuser (the vector index),
// since results can come back out of order. Ops whose unit is left out by the
// parameters must return out_error.
// Generate vectors first:  python3 fpr_top_gen_vectors.py
// Then compile fpr_top_tb.sv with fpr_top.sv and every unit file (see HOW_TO_USE_README.md).
`include "fpr_top_ops.vh"

module fpr_top_tb #(
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
  parameter OPERAND_ISOLATION      = 1
);
  localparam MAX_VEC = 300000;
  localparam TW      = 20;

  reg          clk = 0;
  reg          rst_n = 0;
  reg          in_tvalid = 0;
  wire         in_tready;
  reg  [4:0]   in_op = 0;
  reg  [TW-1:0] in_tuser = 0;
  reg  [63:0]  in1 = 0, in2 = 0, in3 = 0;
  wire         out_tvalid, out_error;
  wire [4:0]   out_op;
  wire [TW-1:0] out_tuser;
  wire [63:0]  out_d1, out_d2, out_d3;

  reg  [7:0]   vec_op  [0:MAX_VEC-1];
  reg  [3:0]   vec_chk [0:MAX_VEC-1];
  reg  [191:0] vec_in  [0:MAX_VEC-1];
  reg  [191:0] vec_exp [0:MAX_VEC-1];
  reg          done    [0:MAX_VEC-1];
  reg  [7:0]   o;
  reg  [3:0]   c;
  reg  [63:0]  v [0:6];
  reg          fire, exp_err;
  integer      fd, r, i, idx, nvec = 0, n_out = 0, n_err_ops = 0, err = 0, cycles = 0, stalls = 0;

  fpr_top #(
    .INCLUDE_ADD            (INCLUDE_ADD),
    .INCLUDE_MUL            (INCLUDE_MUL),
    .INCLUDE_FMA            (INCLUDE_FMA),
    .FMA_ONLY_CORE          (FMA_ONLY_CORE),
    .FUSED                  (FUSED),
    .FMA_REG_STAGES         (FMA_REG_STAGES),
    .INCLUDE_TO_INT         (INCLUDE_TO_INT),
    .INCLUDE_INT2FPR        (INCLUDE_INT2FPR),
    .INCLUDE_INT_MUL        (INCLUDE_INT_MUL),
    .DIVSQRT                (DIVSQRT),
    .DIVSQRT_BITS_PER_CYCLE (DIVSQRT_BITS_PER_CYCLE),
    .DIVSQRT_PIPELINED      (DIVSQRT_PIPELINED),
    .OPERAND_ISOLATION      (OPERAND_ISOLATION),
    .TUSER_W                (TW)
  ) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .in_tvalid  (in_tvalid),
    .in_tready  (in_tready),
    .in_op      (in_op),
    .in_tuser   (in_tuser),
    .in1_tdata  (in1),
    .in2_tdata  (in2),
    .in3_tdata  (in3),
    .out_tvalid (out_tvalid),
    .out_op     (out_op),
    .out_tuser  (out_tuser),
    .out_error  (out_error),
    .out_tdata  (out_d1),
    .out_tdata2 (out_d2),
    .out_tdata3 (out_d3)
  );

  // Which ops this configuration supports (mirrors fpr_top's decode)
  function supported(input [4:0] op);
    case (op)
      `FPR_OP_ADD, `FPR_OP_SUB:                                supported = FMA_ONLY_CORE || INCLUDE_ADD;
      `FPR_OP_MUL:                                             supported = FMA_ONLY_CORE || INCLUDE_MUL;
      `FPR_OP_FMA, `FPR_OP_FMS, `FPR_OP_FNMA, `FPR_OP_FNMS:    supported = FMA_ONLY_CORE || INCLUDE_FMA;
      `FPR_OP_FLOOR, `FPR_OP_CEIL, `FPR_OP_TRUNC, `FPR_OP_ROUND: supported = INCLUDE_TO_INT;
      `FPR_OP_INT2FPR:                                         supported = INCLUDE_INT2FPR;
      `FPR_OP_DIV, `FPR_OP_INV, `FPR_OP_SQRT:                  supported = (DIVSQRT != 0);
      `FPR_OP_INT64_MUL, `FPR_OP_UINT64_MUL:                   supported = INCLUDE_INT_MUL;
      default:                                                 supported = 0;
    endcase
  endfunction

  always #5 clk = ~clk;

  // Result checker, by tag
  always @(negedge clk) begin
    if (rst_n && out_tvalid) begin
      idx = out_tuser;
      n_out = n_out + 1;
      exp_err = !supported(vec_op[idx][4:0]);
      if (done[idx] || out_op !== vec_op[idx][4:0] || out_error !== exp_err ||
          (!exp_err && ((vec_chk[idx][0] && out_d1 !== vec_exp[idx][191:128]) ||
                        (vec_chk[idx][1] && out_d2 !== vec_exp[idx][127:64]) ||
                        (vec_chk[idx][2] && out_d3 !== vec_exp[idx][63:0])))) begin
        err = err + 1;
        if (err <= 10)
          $display("MISMATCH #%0d op=%h err=%0d (exp %0d) in=%h\n  got=%h %h %h\n  exp=%h", idx, out_op, out_error, exp_err,
                   vec_in[idx], out_d1, out_d2, out_d3, vec_exp[idx]);
      end
      if (exp_err) n_err_ops = n_err_ops + 1;
      done[idx] = 1'b1;
    end
  end

  initial begin
    fd = $fopen("fpr_top_vectors.hex", "r");
    if (fd == 0) begin
      $display("ERROR: fpr_top_vectors.hex not found. Run fpr_top_gen_vectors.py first.");
      $finish;
    end
    while (!$feof(fd) && nvec < MAX_VEC) begin
      r = $fscanf(fd, "%2h%1h%16h%16h%16h%16h%16h%16h%16h\n", o, c, v[0], v[1], v[2], v[3], v[4], v[5], v[6]);
      if (r == 9) begin
        vec_op[nvec] = o; vec_chk[nvec] = c; done[nvec] = 1'b0;
        vec_in[nvec]  = {v[0], v[1], v[2]};
        vec_exp[nvec] = {(FUSED ? v[3] : v[6]), v[4], v[5]};
        nvec = nvec + 1;
      end
    end
    $fclose(fd);

    @(posedge clk); @(posedge clk);
    rst_n = 1;

    i = 0;
    while (i < nvec) begin
      @(negedge clk);
      cycles = cycles + 1;
      if (($urandom % 8) == 0) begin
        in_tvalid = 0;
      end else begin
        in_op = vec_op[i][4:0]; in_tuser = i;
        {in1, in2, in3} = vec_in[i];
        in_tvalid = 1;
      end
      #1 fire = in_tvalid & in_tready; // in_tready depends on in_op and the reservation state
      if (in_tvalid & ~in_tready) stalls = stalls + 1;
      @(posedge clk);
      if (fire) i = i + 1;
    end
    @(negedge clk);
    in_tvalid = 0;
    repeat (80) @(negedge clk);

    for (i = 0; i < nvec; i = i + 1) if (!done[i]) err = err + 1;
    $display("fpr_top FMA_ONLY_CORE=%0d FUSED=%0d FMA_REG_STAGES=%0d DIVSQRT=%0d K=%0d PIPELINED=%0d: checked %0d results (%0d out_error as expected) in %0d cycles (%0d stalls), %0d errors -> %s",
             FMA_ONLY_CORE, FUSED, FMA_REG_STAGES, DIVSQRT, DIVSQRT_BITS_PER_CYCLE, DIVSQRT_PIPELINED,
             n_out, n_err_ops, cycles, stalls, err, (err == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
