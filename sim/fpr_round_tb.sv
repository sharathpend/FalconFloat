`timescale 1ns/1ps

// Self-checking testbench for fpr_round.
// Generate vectors first:  python3 fpr_round_gen_vectors.py
// Then:  iverilog -g2012 fpr_round_tb.sv fpr_round.sv && vvp a.out
module fpr_round_tb;
  reg         clk = 0;
  reg         rst_n = 0;
  reg         in_tvalid = 0;
  reg  [63:0] in_tdata = 0;
  wire        out_tvalid;
  wire [63:0] out_tdata;

  reg  [63:0] vec_in, vec_exp;
  integer     fd, r, n = 0, err = 0;

  fpr_round dut (
    .clk                  (clk),
    .rst_n                (rst_n),
    .fpr_round_in_tvalid  (in_tvalid),
    .fpr_round_in_tdata   (in_tdata),
    .fpr_round_out_tvalid (out_tvalid),
    .fpr_round_out_tdata  (out_tdata)
  );

  always #5 clk = ~clk;

  initial begin
    fd = $fopen("fpr_round_vectors.hex", "r");
    if (fd == 0) begin
      $display("ERROR: fpr_round_vectors.hex not found. Run fpr_round_gen_vectors.py first.");
      $finish;
    end

    @(posedge clk); @(posedge clk);
    rst_n = 1;

    while (!$feof(fd)) begin
      r = $fscanf(fd, "%16h%16h\n", vec_in, vec_exp);
      if (r == 2) begin
        @(negedge clk);
        in_tdata = vec_in; in_tvalid = 1;
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

    $display("fpr_round: checked %0d vectors, %0d errors -> %s", n, err, (err == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
