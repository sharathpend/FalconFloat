
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`timescale 1ns/1ps

// Self-checking testbench for fpr_mac. Drives the accumulate steps in order with
// random idle cycles, honors in_tready, and checks the accumulator after each step.
// Generate vectors first:  python3 fpr_mac_gen_vectors.py
// Then:  iverilog -g2012 -P fpr_mac_tb.FUSED=1 -P fpr_mac_tb.REG_STAGES=1 fpr_mac_tb.sv fpr_mac.sv fpr_fma.sv leading_one_calc.sv && vvp a.out
module fpr_mac_tb #(
  parameter FUSED         = 1,
  parameter REG_STAGES    = 1,
  parameter INTERNAL_MULT = 0
);
  localparam MAX_VEC = 200000;
  localparam INVALID = 64'hFFFF_FFFF_FFFF_FFFF; // out of scope for this mode, not checked

  reg          clk = 0;
  reg          rst_n = 0;
  reg          in_tvalid = 0;
  wire         in_tready;
  reg  [63:0]  in1 = 0, in2 = 0;
  reg  [1:0]   op = 0;
  reg          acc_clear = 0;
  wire         out_tvalid;
  wire [63:0]  out_tdata;

  wire [63:0]  mult_in1, mult_in2;
  wire [127:0] mult_result;

  reg  [63:0]  vec_a [0:MAX_VEC-1];
  reg  [63:0]  vec_b [0:MAX_VEC-1];
  reg  [3:0]   vec_op [0:MAX_VEC-1];
  reg  [3:0]   vec_clear [0:MAX_VEC-1];
  reg  [63:0]  vec_exp [0:MAX_VEC-1];
  reg  [63:0]  a, b, ef, eu;
  reg  [3:0]   o, cl;
  reg          fire;
  integer      fd, r, i, nvec = 0, k = 0, n = 0, skipped = 0, err = 0, cycles = 0;

  fpr_mac #(
    .FUSED         (FUSED),
    .REG_STAGES    (REG_STAGES),
    .INTERNAL_MULT (INTERNAL_MULT)
  ) dut (
    .clk                  (clk),
    .rst_n                (rst_n),
    .fpr_mac_in_tvalid    (in_tvalid),
    .fpr_mac_in_tready    (in_tready),
    .fpr_mac_in1_tdata    (in1),
    .fpr_mac_in2_tdata    (in2),
    .fpr_mac_op           (op),
    .fpr_mac_in_acc_clear (acc_clear),
    .uint64_mult_in1      (mult_in1),
    .uint64_mult_in2      (mult_in2),
    .uint64_mult_result   (mult_result),
    .fpr_mac_out_tvalid   (out_tvalid),
    .fpr_mac_out_tdata    (out_tdata)
  );

  // Shared multiplier (ignored when INTERNAL_MULT = 1)
  assign mult_result = INTERNAL_MULT ? 128'd0 : mult_in1 * mult_in2;

  always #5 clk = ~clk;

  // Accumulator checker, in order
  always @(negedge clk) begin
    if (rst_n && out_tvalid) begin
      if (vec_exp[k] === INVALID) begin
        skipped = skipped + 1;
      end else begin
        n = n + 1;
        if (out_tdata !== vec_exp[k]) begin
          err = err + 1;
          if (err <= 10)
            $display("MISMATCH step=%0d a=%h b=%h op=%0d clear=%0d got=%h exp=%h", k, vec_a[k], vec_b[k], vec_op[k], vec_clear[k], out_tdata, vec_exp[k]);
        end
      end
      k = k + 1;
    end
  end

  initial begin
    fd = $fopen("fpr_mac_vectors.hex", "r");
    if (fd == 0) begin
      $display("ERROR: fpr_mac_vectors.hex not found. Run fpr_mac_gen_vectors.py first.");
      $finish;
    end
    while (!$feof(fd) && nvec < MAX_VEC) begin
      r = $fscanf(fd, "%16h%16h%1h%1h%16h%16h\n", a, b, o, cl, ef, eu);
      if (r == 6) begin
        vec_a[nvec] = a; vec_b[nvec] = b; vec_op[nvec] = o; vec_clear[nvec] = cl;
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
      cycles = cycles + 1;
      if (($urandom % 8) == 0) begin
        in_tvalid = 0;
      end else begin
        in1 = vec_a[i]; in2 = vec_b[i]; op = vec_op[i][1:0]; acc_clear = vec_clear[i][0];
        in_tvalid = 1;
      end
      #1 fire = in_tvalid & in_tready; // in_tready only changes on a clock edge
      @(posedge clk);
      if (fire) i = i + 1;
    end
    @(negedge clk);
    in_tvalid = 0;
    repeat (REG_STAGES + 2) @(negedge clk);

    if (k != nvec) err = err + 1;
    $display("fpr_mac FUSED=%0d REG_STAGES=%0d INTERNAL_MULT=%0d: checked %0d steps (%0d out of scope) in %0d cycles, %0d errors -> %s",
             FUSED, REG_STAGES, INTERNAL_MULT, n, skipped, cycles, err, (err == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
