
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`timescale 1ns/1ps

// Self-checking testbench for fpr_sqrt. Streams the vectors with random idle
// cycles, honors in_tready and checks the outputs in order.
// Generate vectors first:  python3 fpr_sqrt_gen_vectors.py
// Then:  iverilog -g2012 -P fpr_sqrt_tb.BITS_PER_CYCLE=2 -P fpr_sqrt_tb.PIPELINED=0 fpr_sqrt_tb.sv fpr_sqrt.sv && vvp a.out
module fpr_sqrt_tb #(
  parameter BITS_PER_CYCLE = 2,
  parameter PIPELINED      = 0
);
  localparam MAX_VEC = 400000;

  reg         clk = 0;
  reg         rst_n = 0;
  reg         in_tvalid = 0;
  wire        in_tready;
  reg  [63:0] in1 = 0;
  wire        out_tvalid;
  wire [63:0] out_tdata;

  reg  [63:0] vec_a [0:MAX_VEC-1];
  reg  [63:0] vec_q [0:MAX_VEC-1];
  reg  [63:0] a, q;
  reg         fire;
  integer     fd, r, i, nvec = 0, k = 0, err = 0, cycles = 0;

  fpr_sqrt #(
    .BITS_PER_CYCLE (BITS_PER_CYCLE),
    .PIPELINED      (PIPELINED)
  ) dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .fpr_sqrt_in_tvalid  (in_tvalid),
    .fpr_sqrt_in_tready  (in_tready),
    .fpr_sqrt_in_tdata   (in1),
    .fpr_sqrt_out_tvalid (out_tvalid),
    .fpr_sqrt_out_tdata  (out_tdata)
  );

  always #5 clk = ~clk;

  // Output checker, in order
  always @(negedge clk) begin
    if (rst_n && out_tvalid) begin
      if (out_tdata !== vec_q[k]) begin
        err = err + 1;
        if (err <= 10)
          $display("MISMATCH x=%h got=%h exp=%h", vec_a[k], out_tdata, vec_q[k]);
      end
      k = k + 1;
    end
  end

  initial begin
    fd = $fopen("fpr_sqrt_vectors.hex", "r");
    if (fd == 0) begin
      $display("ERROR: fpr_sqrt_vectors.hex not found. Run fpr_sqrt_gen_vectors.py first.");
      $finish;
    end
    while (!$feof(fd) && nvec < MAX_VEC) begin
      r = $fscanf(fd, "%16h%16h\n", a, q);
      if (r == 2) begin
        vec_a[nvec] = a; vec_q[nvec] = q;
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
        in1 = vec_a[i];
        in_tvalid = 1;
      end
      #1 fire = in_tvalid & in_tready; // in_tready only changes on a clock edge
      @(posedge clk);
      if (fire) i = i + 1;
    end
    @(negedge clk);
    in_tvalid = 0;
    repeat (64) @(negedge clk);

    if (k != nvec) err = err + 1;
    $display("fpr_sqrt BITS_PER_CYCLE=%0d PIPELINED=%0d: checked %0d vectors in %0d cycles, %0d errors -> %s",
             BITS_PER_CYCLE, PIPELINED, k, cycles, err, (err == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
