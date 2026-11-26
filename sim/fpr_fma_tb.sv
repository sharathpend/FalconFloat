
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`timescale 1ns/1ps

// Self-checking testbench for fpr_fma. Streams one vector per cycle with random
// idle cycles and checks the outputs in order, so it works for any REG_STAGES.
// INTERNAL_MULT = 0 runs through fpr_fma_top (shared multiplier in the loop).
// Generate vectors first:  python3 fpr_fma_gen_vectors.py
// Then:  iverilog -g2012 -P fpr_fma_tb.FUSED=1 -P fpr_fma_tb.REG_STAGES=1 fpr_fma_tb.sv fpr_fma_top.sv fpr_fma.sv leading_one_calc.sv && vvp a.out
module fpr_fma_tb #(
  parameter FUSED         = 1,
  parameter REG_STAGES    = 1,
  parameter INTERNAL_MULT = 0
);
  localparam MAX_VEC = 400000;
  localparam INVALID = 64'hFFFF_FFFF_FFFF_FFFF; // out of scope for this mode, not checked

  reg         clk = 0;
  reg         rst_n = 0;
  reg         in_tvalid = 0;
  reg  [63:0] in1 = 0, in2 = 0, in3 = 0;
  reg  [1:0]  op = 0;
  wire        out_tvalid;
  wire [63:0] out_tdata;

  reg  [63:0] vec_a [0:MAX_VEC-1];
  reg  [63:0] vec_b [0:MAX_VEC-1];
  reg  [63:0] vec_c [0:MAX_VEC-1];
  reg  [3:0]  vec_op [0:MAX_VEC-1];
  reg  [63:0] vec_exp [0:MAX_VEC-1];
  reg  [63:0] a, b, c, ef, eu;
  reg  [3:0]  o;
  integer     fd, r, i, nvec = 0, k = 0, n = 0, skipped = 0, err = 0;

  generate
    if (INTERNAL_MULT) begin : gen_standalone
      wire [63:0] unused_mult_in1, unused_mult_in2;

      fpr_fma #(
        .FUSED         (FUSED),
        .REG_STAGES    (REG_STAGES),
        .INTERNAL_MULT (1)
      ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .fpr_fma_in_tvalid  (in_tvalid),
        .fpr_fma_in1_tdata  (in1),
        .fpr_fma_in2_tdata  (in2),
        .fpr_fma_in3_tdata  (in3),
        .fpr_fma_op         (op),
        .uint64_mult_in1    (unused_mult_in1),
        .uint64_mult_in2    (unused_mult_in2),
        .uint64_mult_result (128'd0),
        .fpr_fma_out_tvalid (out_tvalid),
        .fpr_fma_out_tdata  (out_tdata)
      );
    end else begin : gen_shared
      fpr_fma_top #(
        .FUSED      (FUSED),
        .REG_STAGES (REG_STAGES)
      ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .fpr_fma_in_tvalid  (in_tvalid),
        .fpr_fma_in1_tdata  (in1),
        .fpr_fma_in2_tdata  (in2),
        .fpr_fma_in3_tdata  (in3),
        .fpr_fma_op         (op),
        .fpr_fma_out_tvalid (out_tvalid),
        .fpr_fma_out_tdata  (out_tdata)
      );
    end
  endgenerate

  always #5 clk = ~clk;

  // Output checker, in order
  always @(negedge clk) begin
    if (rst_n && out_tvalid) begin
      if (vec_exp[k] === INVALID) begin
        skipped = skipped + 1;
      end else begin
        n = n + 1;
        if (out_tdata !== vec_exp[k]) begin
          err = err + 1;
          if (err <= 10)
            $display("MISMATCH a=%h b=%h c=%h op=%0d got=%h exp=%h", vec_a[k], vec_b[k], vec_c[k], vec_op[k], out_tdata, vec_exp[k]);
        end
      end
      k = k + 1;
    end
  end

  initial begin
    fd = $fopen("fpr_fma_vectors.hex", "r");
    if (fd == 0) begin
      $display("ERROR: fpr_fma_vectors.hex not found. Run fpr_fma_gen_vectors.py first.");
      $finish;
    end
    while (!$feof(fd) && nvec < MAX_VEC) begin
      r = $fscanf(fd, "%16h%16h%16h%1h%16h%16h\n", a, b, c, o, ef, eu);
      if (r == 6) begin
        vec_a[nvec] = a; vec_b[nvec] = b; vec_c[nvec] = c; vec_op[nvec] = o;
        vec_exp[nvec] = FUSED ? ef : eu;
        nvec = nvec + 1;
      end
    end
    $fclose(fd);

    @(posedge clk); @(posedge clk);
    rst_n = 1;

    i = 0;
    while (i < nvec) begin
      @(negedge clk);
      if (($urandom % 8) == 0) begin
        in_tvalid = 0;
      end else begin
        in1 = vec_a[i]; in2 = vec_b[i]; in3 = vec_c[i]; op = vec_op[i][1:0];
        in_tvalid = 1;
        i = i + 1;
      end
    end
    @(negedge clk);
    in_tvalid = 0;
    repeat (REG_STAGES + 2) @(negedge clk);

    if (k != nvec) err = err + 1;
    $display("fpr_fma FUSED=%0d REG_STAGES=%0d INTERNAL_MULT=%0d: checked %0d vectors (%0d out of scope), %0d errors -> %s",
             FUSED, REG_STAGES, INTERNAL_MULT, n, skipped, err, (err == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
