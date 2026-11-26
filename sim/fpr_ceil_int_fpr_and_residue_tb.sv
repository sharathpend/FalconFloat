
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`timescale 1ns/1ps

// Self-checking testbench for fpr_ceil_int_fpr_and_residue.
// Generate vectors first:  python3 fpr_ceil_int_fpr_and_residue_gen_vectors.py
// Then:  iverilog -g2012 fpr_ceil_int_fpr_and_residue_tb.sv fpr_ceil_int_fpr_and_residue.sv fpr_ceil_and_residue.sv leading_one_calc.sv && vvp a.out
module fpr_ceil_int_fpr_and_residue_tb;
  reg         clk = 0;
  reg         rst_n = 0;
  reg         in_tvalid = 0;
  reg  [63:0] in_tdata = 0;
  wire        out_tvalid;
  wire [63:0] out_ceil_int;
  wire [63:0] out_ceil_fpr;
  wire [63:0] out_residue;

  reg  [63:0] vec_in, vec_ceil_int, vec_ceil_fpr, vec_residue;
  integer     fd, r, n = 0, err_ceil_int = 0, err_ceil_fpr = 0, err_residue = 0;

  fpr_ceil_int_fpr_and_residue dut (
    .clk                                       (clk),
    .rst_n                                     (rst_n),
    .fpr_ceil_int_fpr_and_residue_in_tvalid    (in_tvalid),
    .fpr_ceil_int_fpr_and_residue_in_tdata     (in_tdata),
    .fpr_ceil_int_fpr_and_residue_out_tvalid   (out_tvalid),
    .fpr_ceil_int_fpr_and_residue_out_ceil_int (out_ceil_int),
    .fpr_ceil_int_fpr_and_residue_out_ceil_fpr (out_ceil_fpr),
    .fpr_ceil_int_fpr_and_residue_out_residue  (out_residue)
  );

  always #5 clk = ~clk;

  initial begin
    fd = $fopen("fpr_ceil_int_fpr_and_residue_vectors.hex", "r");
    if (fd == 0) begin
      $display("ERROR: fpr_ceil_int_fpr_and_residue_vectors.hex not found. Run fpr_ceil_int_fpr_and_residue_gen_vectors.py first.");
      $finish;
    end

    @(posedge clk); @(posedge clk);
    rst_n = 1;

    while (!$feof(fd)) begin
      r = $fscanf(fd, "%16h%16h%16h%16h\n", vec_in, vec_ceil_int, vec_ceil_fpr, vec_residue);
      if (r == 4) begin
        @(negedge clk);
        in_tdata = vec_in; in_tvalid = 1;
        @(posedge clk); #1;   // 1-cycle latency
        n = n + 1;
        if (!out_tvalid || out_ceil_int !== vec_ceil_int) begin
          err_ceil_int = err_ceil_int + 1;
          if (err_ceil_int <= 5)
            $display("CEIL INT MISMATCH   in=%h got=%h exp=%h", vec_in, out_ceil_int, vec_ceil_int);
        end
        if (!out_tvalid || out_ceil_fpr !== vec_ceil_fpr) begin
          err_ceil_fpr = err_ceil_fpr + 1;
          if (err_ceil_fpr <= 5)
            $display("CEIL FPR MISMATCH   in=%h got=%h exp=%h", vec_in, out_ceil_fpr, vec_ceil_fpr);
        end
        if (!out_tvalid || out_residue !== vec_residue) begin
          err_residue = err_residue + 1;
          if (err_residue <= 5)
            $display("RESIDUE MISMATCH    in=%h got=%h exp=%h", vec_in, out_residue, vec_residue);
        end
      end
    end
    $fclose(fd);

    $display("fpr_ceil_int_fpr_and_residue: checked %0d vectors, ceil int errors %0d, ceil fpr errors %0d, residue errors %0d -> %s",
             n, err_ceil_int, err_ceil_fpr, err_residue, (err_ceil_int + err_ceil_fpr + err_residue == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
