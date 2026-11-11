`timescale 1ns/1ps

// Self-checking testbench for fpr_mul, driven through fpr_mul_top with fpr_mul_op = 0
// so the shared multiplier is in the loop.
// Generate vectors first:  python3 fpr_mul_gen_vectors.py
// Then:  iverilog -g2012 fpr_mul_tb.sv fpr_mul_top.sv fpr_mul.sv int64_mul.sv && vvp a.out
module fpr_mul_tb;
  reg          clk = 0;
  reg          rst_n = 0;
  reg          in_tvalid = 0;
  reg  [63:0]  in1 = 0, in2 = 0;
  wire         out_tvalid;
  wire [63:0]  out_tdata;
  wire         int64_out_tvalid;
  wire [127:0] int64_out_tdata;

  reg  [63:0]  vec_a, vec_b, vec_exp;
  integer      fd, r, n = 0, err = 0;

  fpr_mul_top dut (
    .clk                  (clk),
    .rst_n                (rst_n),
    .fpr_mul_in_tvalid    (in_tvalid),
    .fpr_mul_in1_tdata    (in1),
    .fpr_mul_in2_tdata    (in2),
    .fpr_mul_op           (1'b0),
    .fpr_mul_out_tvalid   (out_tvalid),
    .fpr_mul_out_tdata    (out_tdata),
    .int64_mul_out_tvalid (int64_out_tvalid),
    .int64_mul_out_tdata  (int64_out_tdata)
  );

  always #5 clk = ~clk;

  initial begin
    fd = $fopen("fpr_mul_vectors.hex", "r");
    if (fd == 0) begin
      $display("ERROR: fpr_mul_vectors.hex not found. Run fpr_mul_gen_vectors.py first.");
      $finish;
    end

    @(posedge clk); @(posedge clk);
    rst_n = 1;

    while (!$feof(fd)) begin
      r = $fscanf(fd, "%16h%16h%16h\n", vec_a, vec_b, vec_exp);
      if (r == 3) begin
        @(negedge clk);
        in1 = vec_a; in2 = vec_b; in_tvalid = 1;
        @(posedge clk); #1;   // 1-cycle latency
        n = n + 1;
        if (!out_tvalid || out_tdata !== vec_exp) begin
          err = err + 1;
          if (err <= 10)
            $display("MISMATCH in1=%h in2=%h got=%h exp=%h", vec_a, vec_b, out_tdata, vec_exp);
        end
      end
    end
    $fclose(fd);

    $display("fpr_mul: checked %0d vectors, %0d errors -> %s", n, err, (err == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
