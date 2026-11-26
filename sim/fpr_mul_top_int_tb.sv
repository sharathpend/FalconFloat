
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`timescale 1ns/1ps

// Self-checking testbench for the integer paths of fpr_mul_top (int64 mul and the
// full 128-bit uint64 mul), with the op changing every cycle so the shared multiplier
// is switched between users. The fp mul path is checked by fpr_mul_tb, and fpr_top's
// int muls by fpr_top_tb. Reference is computed in the testbench.
// Run:  iverilog -g2012 fpr_mul_top_int_tb.sv fpr_mul_top.sv fpr_mul.sv int64_mul.sv uint64_mul.sv
//                uint_mul_core.sv karatsuba_mul.sv comba_mul.sv && vvp a.out
module fpr_mul_top_int_tb #(
  parameter NUM_RANDOM = 50000
);
  reg          clk = 0;
  reg          rst_n = 0;
  reg          in_tvalid = 0;
  reg  [63:0]  in1 = 0, in2 = 0;
  reg  [1:0]   op = 0;            // 0 = fp mul, 1 = int64 mul, 2 = uint64 mul

  wire         mt_fp_tvalid, mt_i64_tvalid, mt_u64_tvalid;
  wire [63:0]  mt_fp_tdata;
  wire [127:0] mt_i64_tdata, mt_u64_tdata;

  reg  [63:0]  a, b;
  reg  [1:0]   o;
  reg  [62:0]  mag_a, mag_b;
  reg  [127:0] exp_i64, exp_u64;
  integer      i, n_i64 = 0, n_u64 = 0, err = 0;

  fpr_mul_top dut_mul_top (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .fpr_mul_in_tvalid     (in_tvalid),
    .fpr_mul_in1_tdata     (in1),
    .fpr_mul_in2_tdata     (in2),
    .fpr_mul_op            (op),
    .fpr_mul_out_tvalid    (mt_fp_tvalid),
    .fpr_mul_out_tdata     (mt_fp_tdata),
    .int64_mul_out_tvalid  (mt_i64_tvalid),
    .int64_mul_out_tdata   (mt_i64_tdata),
    .uint64_mul_out_tvalid (mt_u64_tvalid),
    .uint64_mul_out_tdata  (mt_u64_tdata)
  );

  always #5 clk = ~clk;

  initial begin
    @(posedge clk); @(posedge clk);
    rst_n = 1;
    for (i = 0; i < NUM_RANDOM; i = i + 1) begin
      a = {$urandom, $urandom}; b = {$urandom, $urandom};
      if (i < 64) begin a = ~64'd0; b = (i[0]) ? ~64'd0 : (64'd1 << i); end
      o = $urandom % 3;
      @(negedge clk);
      in1 = a; in2 = b; op = o; in_tvalid = 1;
      @(posedge clk); #1;   // 1-cycle latency
      mag_a = a[62:0]; mag_b = b[62:0];
      exp_i64 = {a[63] ^ b[63], 1'b0, 126'(mag_a * mag_b)};
      exp_u64 = a * b;
      if (o == 2'd1) begin
        n_i64 = n_i64 + 1;
        if (!mt_i64_tvalid || mt_i64_tdata !== exp_i64) begin
          err = err + 1;
          if (err <= 10) $display("INT64 MISMATCH  a=%h b=%h got=%h exp=%h", a, b, mt_i64_tdata, exp_i64);
        end
      end
      if (o == 2'd2) begin
        n_u64 = n_u64 + 1;
        if (!mt_u64_tvalid || mt_u64_tdata !== exp_u64) begin
          err = err + 1;
          if (err <= 10) $display("UINT64 MISMATCH a=%h b=%h got=%h exp=%h", a, b, mt_u64_tdata, exp_u64);
        end
      end
      if ((mt_u64_tvalid != (o == 2'd2)) || (mt_i64_tvalid != (o == 2'd1)) || (mt_fp_tvalid != (o == 2'd0))) begin
        err = err + 1;
        if (err <= 10) $display("TVALID MISMATCH op=%0d", o);
      end
    end
    $display("fpr_mul_top_int: checked %0d int64 and %0d uint64 vectors, %0d errors -> %s",
             n_i64, n_u64, err, (err == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
