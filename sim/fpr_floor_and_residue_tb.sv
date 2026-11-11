`timescale 1ns/1ps

// Self-checking testbench for fpr_floor_and_residue.
// Generate vectors first:  python3 fpr_floor_and_residue_gen_vectors.py
// Then:  iverilog -g2012 fpr_floor_and_residue_tb.sv fpr_floor_and_residue.sv leading_one_calc.sv && vvp a.out
module fpr_floor_and_residue_tb;
  reg         clk = 0;
  reg         rst_n = 0;
  reg         in_tvalid = 0;
  reg  [63:0] in_tdata = 0;
  wire        out_tvalid;
  wire [63:0] out_floor;
  wire [63:0] out_residue;

  reg  [63:0] vec_in, vec_floor, vec_residue;
  integer     fd, r, n = 0, err_floor = 0, err_residue = 0;

  fpr_floor_and_residue dut (
    .clk                               (clk),
    .rst_n                             (rst_n),
    .fpr_floor_and_residue_in_tvalid   (in_tvalid),
    .fpr_floor_and_residue_in_tdata    (in_tdata),
    .fpr_floor_and_residue_out_tvalid  (out_tvalid),
    .fpr_floor_and_residue_out_floor   (out_floor),
    .fpr_floor_and_residue_out_residue (out_residue)
  );

  always #5 clk = ~clk;

  initial begin
    fd = $fopen("fpr_floor_and_residue_vectors.hex", "r");
    if (fd == 0) begin
      $display("ERROR: fpr_floor_and_residue_vectors.hex not found. Run fpr_floor_and_residue_gen_vectors.py first.");
      $finish;
    end

    @(posedge clk); @(posedge clk);
    rst_n = 1;

    while (!$feof(fd)) begin
      r = $fscanf(fd, "%16h%16h%16h\n", vec_in, vec_floor, vec_residue);
      if (r == 3) begin
        @(negedge clk);
        in_tdata = vec_in; in_tvalid = 1;
        @(posedge clk); #1;   // 1-cycle latency
        n = n + 1;
        if (!out_tvalid || out_floor !== vec_floor) begin
          err_floor = err_floor + 1;
          if (err_floor <= 5)
            $display("FLOOR MISMATCH   in=%h got=%h exp=%h", vec_in, out_floor, vec_floor);
        end
        if (!out_tvalid || out_residue !== vec_residue) begin
          err_residue = err_residue + 1;
          if (err_residue <= 5)
            $display("RESIDUE MISMATCH in=%h got=%h exp=%h", vec_in, out_residue, vec_residue);
        end
      end
    end
    $fclose(fd);

    $display("fpr_floor_and_residue: checked %0d vectors, floor errors %0d, residue errors %0d -> %s",
             n, err_floor, err_residue, (err_floor + err_residue == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
