
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`timescale 1ns/1ps

// Self-checking testbench for fpr_to_int. Each vector has a check mask, so other
// vector files (e.g. the old per-module ones, converted) can be replayed too.
// Generate vectors first:  python3 fpr_to_int_gen_vectors.py
// Then:  iverilog -g2012 fpr_to_int_tb.sv fpr_to_int.sv leading_one_calc.sv && vvp a.out
// Another file:  vvp a.out +VECTORS=<file>
module fpr_to_int_tb;
  reg         clk = 0;
  reg         rst_n = 0;
  reg         in_tvalid = 0;
  reg  [63:0] in_tdata = 0;
  reg  [1:0]  mode = 0;
  wire        out_tvalid;
  wire [63:0] out_int, out_fpr, out_residue;

  reg  [3:0]  vec_mode, vec_chk;
  reg  [63:0] vec_in, vec_int, vec_fpr, vec_res;
  reg  [8*256-1:0] fname;
  integer     fd, r, n = 0, err_int = 0, err_fpr = 0, err_res = 0;

  fpr_to_int dut (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .fpr_to_int_in_tvalid   (in_tvalid),
    .fpr_to_int_in_tdata    (in_tdata),
    .fpr_to_int_mode        (mode),
    .fpr_to_int_out_tvalid  (out_tvalid),
    .fpr_to_int_out_int     (out_int),
    .fpr_to_int_out_fpr     (out_fpr),
    .fpr_to_int_out_residue (out_residue)
  );

  always #5 clk = ~clk;

  initial begin
    if (!$value$plusargs("VECTORS=%s", fname)) fname = "fpr_to_int_vectors.hex";
    fd = $fopen(fname, "r");
    if (fd == 0) begin
      $display("ERROR: %0s not found. Run fpr_to_int_gen_vectors.py first.", fname);
      $finish;
    end

    @(posedge clk); @(posedge clk);
    rst_n = 1;

    while (!$feof(fd)) begin
      r = $fscanf(fd, "%1h%1h%16h%16h%16h%16h\n", vec_mode, vec_chk, vec_in, vec_int, vec_fpr, vec_res);
      if (r == 6) begin
        @(negedge clk);
        in_tdata = vec_in; mode = vec_mode[1:0]; in_tvalid = 1;
        @(posedge clk); #1;   // 1-cycle latency
        n = n + 1;
        if (vec_chk[0] && (!out_tvalid || out_int !== vec_int)) begin
          err_int = err_int + 1;
          if (err_int <= 5) $display("INT MISMATCH     mode=%0d in=%h got=%h exp=%h", vec_mode, vec_in, out_int, vec_int);
        end
        if (vec_chk[1] && (!out_tvalid || out_fpr !== vec_fpr)) begin
          err_fpr = err_fpr + 1;
          if (err_fpr <= 5) $display("FPR MISMATCH     mode=%0d in=%h got=%h exp=%h", vec_mode, vec_in, out_fpr, vec_fpr);
        end
        if (vec_chk[2] && (!out_tvalid || out_residue !== vec_res)) begin
          err_res = err_res + 1;
          if (err_res <= 5) $display("RESIDUE MISMATCH mode=%0d in=%h got=%h exp=%h", vec_mode, vec_in, out_residue, vec_res);
        end
      end
    end
    $fclose(fd);

    $display("fpr_to_int: checked %0d vectors, int errors %0d, fpr errors %0d, residue errors %0d -> %s",
             n, err_int, err_fpr, err_res, (err_int + err_fpr + err_res == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
