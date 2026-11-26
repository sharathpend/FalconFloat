
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`timescale 1ns/1ps

// Self-checking testbench for fpr_div_sqrt. Reuses the fpr_div, fpr_inv and fpr_sqrt
// vector files and interleaves them in random order, so divides and square roots
// are mixed. Streams with random idle cycles, honors in_tready, checks in order.
// Generate vectors first:  python3 fpr_div_gen_vectors.py, fpr_inv_gen_vectors.py, fpr_sqrt_gen_vectors.py
// Then:  iverilog -g2012 -P fpr_div_sqrt_tb.BITS_PER_CYCLE=2 -P fpr_div_sqrt_tb.PIPELINED=0 fpr_div_sqrt_tb.sv fpr_div_sqrt.sv && vvp a.out
module fpr_div_sqrt_tb #(
  parameter BITS_PER_CYCLE = 2,
  parameter PIPELINED      = 0
);
  localparam MAX_VEC = 400000; // per file

  reg         clk = 0;
  reg         rst_n = 0;
  reg         in_tvalid = 0;
  wire        in_tready;
  reg         op = 0;
  reg  [63:0] in1 = 0, in2 = 0;
  wire        out_tvalid;
  wire [63:0] out_tdata;

  reg  [63:0] vec_a  [0:3*MAX_VEC-1];
  reg  [63:0] vec_b  [0:3*MAX_VEC-1];
  reg  [63:0] vec_q  [0:3*MAX_VEC-1];
  reg         vec_op [0:3*MAX_VEC-1];
  reg  [63:0] src_a  [0:2][0:MAX_VEC-1];
  reg  [63:0] src_b  [0:2][0:MAX_VEC-1];
  reg  [63:0] src_q  [0:2][0:MAX_VEC-1];
  integer     src_n  [0:2];
  integer     src_i  [0:2];
  reg  [63:0] a, b, q;
  reg         fire;
  integer     fd, r, f, i, nvec = 0, k = 0, err = 0, cycles = 0, n_sqrt = 0;

  fpr_div_sqrt #(
    .BITS_PER_CYCLE (BITS_PER_CYCLE),
    .PIPELINED      (PIPELINED)
  ) dut (
    .clk                     (clk),
    .rst_n                   (rst_n),
    .fpr_div_sqrt_in_tvalid  (in_tvalid),
    .fpr_div_sqrt_in_tready  (in_tready),
    .fpr_div_sqrt_op         (op),
    .fpr_div_sqrt_in1_tdata  (in1),
    .fpr_div_sqrt_in2_tdata  (in2),
    .fpr_div_sqrt_out_tvalid (out_tvalid),
    .fpr_div_sqrt_out_tdata  (out_tdata)
  );

  always #5 clk = ~clk;

  // Output checker, in order
  always @(negedge clk) begin
    if (rst_n && out_tvalid) begin
      if (out_tdata !== vec_q[k]) begin
        err = err + 1;
        if (err <= 10)
          $display("MISMATCH op=%0d a=%h b=%h got=%h exp=%h", vec_op[k], vec_a[k], vec_b[k], out_tdata, vec_q[k]);
      end
      k = k + 1;
    end
  end

  initial begin
    // 0: fpr_div (a b q), 1: fpr_inv (1.0 x q), 2: fpr_sqrt (x q)
    for (f = 0; f < 3; f = f + 1) begin
      src_n[f] = 0; src_i[f] = 0;
      fd = $fopen((f == 0) ? "fpr_div_vectors.hex" : (f == 1) ? "fpr_inv_vectors.hex" : "fpr_sqrt_vectors.hex", "r");
      if (fd == 0) begin
        $display("ERROR: vector file %0d not found. Run fpr_div_gen_vectors.py, fpr_inv_gen_vectors.py and fpr_sqrt_gen_vectors.py first.", f);
        $finish;
      end
      while (!$feof(fd) && src_n[f] < MAX_VEC) begin
        if (f == 2) begin r = $fscanf(fd, "%16h%16h\n", a, q); b = 64'd0; r = r + 1; end
        else        r = $fscanf(fd, "%16h%16h%16h\n", a, b, q);
        if (r == 3) begin
          src_a[f][src_n[f]] = a; src_b[f][src_n[f]] = b; src_q[f][src_n[f]] = q;
          src_n[f] = src_n[f] + 1;
        end
      end
      $fclose(fd);
    end
    // Interleave the three files in random order
    while (src_i[0] < src_n[0] || src_i[1] < src_n[1] || src_i[2] < src_n[2]) begin
      f = $urandom % 3;
      if (src_i[f] < src_n[f]) begin
        vec_a[nvec] = src_a[f][src_i[f]]; vec_b[nvec] = src_b[f][src_i[f]]; vec_q[nvec] = src_q[f][src_i[f]];
        vec_op[nvec] = (f == 2);
        n_sqrt = n_sqrt + (f == 2);
        src_i[f] = src_i[f] + 1;
        nvec = nvec + 1;
      end
    end

    @(posedge clk); @(posedge clk);
    rst_n = 1;

    i = 0;
    while (i < nvec) begin
      @(negedge clk);
      cycles = cycles + 1;
      if (($urandom % 8) == 0) begin
        in_tvalid = 0;
      end else begin
        op = vec_op[i]; in1 = vec_a[i]; in2 = vec_b[i];
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
    $display("fpr_div_sqrt BITS_PER_CYCLE=%0d PIPELINED=%0d: checked %0d vectors (%0d div/inv, %0d sqrt) in %0d cycles, %0d errors -> %s",
             BITS_PER_CYCLE, PIPELINED, k, nvec - n_sqrt, n_sqrt, cycles, err, (err == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
