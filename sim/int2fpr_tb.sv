`timescale 1ns/1ps

// Self-checking testbench for int2fpr.
// Generate vectors first:  python3 int2fpr_gen_vectors.py
// Then:                    iverilog -g2012 int2fpr_tb.sv int2fpr.sv leading_one_calc.sv && vvp a.out
module int2fpr_tb;
  reg         clk = 0;
  reg         rst_n = 0;
  reg         in_tvalid = 0;
  reg  [63:0] in_tdata = 0;
  wire        out_tvalid;
  wire [63:0] out_tdata;

  reg  [63:0] vec_in, vec_exp;
  integer     fd, r, n = 0, err = 0;

  int2fpr dut (
    .clk                (clk),
    .rst_n              (rst_n),
    .int2fpr_in_tvalid  (in_tvalid),
    .int2fpr_in_tdata   (in_tdata),
    .int2fpr_out_tvalid (out_tvalid),
    .int2fpr_out_tdata  (out_tdata)
  );

  always #5 clk = ~clk;

  initial begin
    fd = $fopen("int2fpr_vectors.hex", "r");
    if (fd == 0) begin
      $display("ERROR: int2fpr_vectors.hex not found. Run int2fpr_gen_vectors.py first.");
      $finish;
    end

    @(posedge clk); @(posedge clk);
    rst_n = 1;

    while (!$feof(fd)) begin
      r = $fscanf(fd, "%16h%16h\n", vec_in, vec_exp);
      if (r == 2) begin
        @(negedge clk);
        in_tdata  = vec_in;
        in_tvalid = 1;
        @(posedge clk); #1;   // 1-cycle latency
        n = n + 1;
        if (!out_tvalid || out_tdata !== vec_exp) begin
          err = err + 1;
          if (err <= 10)
            $display("MISMATCH in=%h got=%h exp=%h", vec_in, out_tdata, vec_exp);
        end
      end
    end
    $fclose(fd);

    @(negedge clk); in_tvalid = 0;
    @(posedge clk); #1;
    if (out_tvalid) begin
      err = err + 1;
      $display("ERROR: out_tvalid did not drop after in_tvalid deasserted");
    end

    $display("int2fpr: checked %0d vectors, %0d errors -> %s", n, err, (err == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
