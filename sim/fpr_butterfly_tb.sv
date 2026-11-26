
/*
Disclaimer: This project is provided "AS IS" without warranty for personal,
educational, and research use. See the LICENSE file for the full terms and
restrictions, including non-commercial use conditions.
*/

/*
Designer: Sharath Pendyala
*/

`timescale 1ns/1ps

// Self-checking testbench for fpr_butterfly. Streams the butterflies with random
// idle cycles, honors in_tready (mode changes) and checks the outputs in order.
// Generate vectors first:  python3 fpr_butterfly_gen_vectors.py
// Then:  iverilog -g2012 -P fpr_butterfly_tb.FUSED=0 -P fpr_butterfly_tb.REG_STAGES=1 fpr_butterfly_tb.sv fpr_butterfly.sv
//                fpr_fma.sv fpr_mul.sv fpr_add.sv fpr_add_norm.sv leading_one_calc.sv uint_mul_core.sv karatsuba_mul.sv comba_mul.sv && vvp a.out
module fpr_butterfly_tb #(
  parameter FUSED      = 0,
  parameter REG_STAGES = 1
);
  localparam MAX_VEC = 200000;
  localparam INVALID = 64'hFFFF_FFFF_FFFF_FFFF; // out of scope for this mode, not checked

  reg          clk = 0;
  reg          rst_n = 0;
  reg          in_tvalid = 0;
  wire         in_tready;
  reg          in_mode = 0, in_conj = 0;
  reg  [63:0]  in_x_re = 0, in_x_im = 0, in_y_re = 0, in_y_im = 0, in_s_re = 0, in_s_im = 0;
  wire         out_tvalid;
  wire [63:0]  out_x_re, out_x_im, out_y_re, out_y_im;

  reg  [7:0]   vec_ctrl [0:MAX_VEC-1];
  reg  [383:0] vec_in   [0:MAX_VEC-1];
  reg  [255:0] vec_exp  [0:MAX_VEC-1];
  reg  [3:0]   m, c;
  reg  [63:0]  v [0:13];
  reg          fire;
  integer      fd, r, i, nvec = 0, k = 0, n = 0, skipped = 0, err = 0, cycles = 0, stalls = 0;

  fpr_butterfly #(
    .FUSED      (FUSED),
    .REG_STAGES (REG_STAGES)
  ) dut (
    .clk                      (clk),
    .rst_n                    (rst_n),
    .fpr_butterfly_in_tvalid  (in_tvalid),
    .fpr_butterfly_in_tready  (in_tready),
    .fpr_butterfly_in_mode    (in_mode),
    .fpr_butterfly_in_conj_s  (in_conj),
    .fpr_butterfly_in_x_re    (in_x_re),
    .fpr_butterfly_in_x_im    (in_x_im),
    .fpr_butterfly_in_y_re    (in_y_re),
    .fpr_butterfly_in_y_im    (in_y_im),
    .fpr_butterfly_in_s_re    (in_s_re),
    .fpr_butterfly_in_s_im    (in_s_im),
    .fpr_butterfly_out_tvalid (out_tvalid),
    .fpr_butterfly_out_x_re   (out_x_re),
    .fpr_butterfly_out_x_im   (out_x_im),
    .fpr_butterfly_out_y_re   (out_y_re),
    .fpr_butterfly_out_y_im   (out_y_im)
  );

  always #5 clk = ~clk;

  // Output checker, in order
  always @(negedge clk) begin
    if (rst_n && out_tvalid) begin
      if (vec_exp[k][255:192] === INVALID) begin
        skipped = skipped + 1;
      end else begin
        n = n + 1;
        if ({out_x_re, out_x_im, out_y_re, out_y_im} !== vec_exp[k]) begin
          err = err + 1;
          if (err <= 10)
            $display("MISMATCH #%0d mode=%0d conj=%0d in=%h\n  got=%h %h %h %h\n  exp=%h %h %h %h", k, vec_ctrl[k][7:4], vec_ctrl[k][3:0], vec_in[k],
                     out_x_re, out_x_im, out_y_re, out_y_im, vec_exp[k][255:192], vec_exp[k][191:128], vec_exp[k][127:64], vec_exp[k][63:0]);
        end
      end
      k = k + 1;
    end
  end

  initial begin
    fd = $fopen("fpr_butterfly_vectors.hex", "r");
    if (fd == 0) begin
      $display("ERROR: fpr_butterfly_vectors.hex not found. Run fpr_butterfly_gen_vectors.py first.");
      $finish;
    end
    while (!$feof(fd) && nvec < MAX_VEC) begin
      r = $fscanf(fd, "%1h%1h%16h%16h%16h%16h%16h%16h%16h%16h%16h%16h%16h%16h%16h%16h\n",
                  m, c, v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12], v[13]);
      if (r == 16) begin
        vec_ctrl[nvec] = {m, c};
        vec_in[nvec]   = {v[0], v[1], v[2], v[3], v[4], v[5]};
        vec_exp[nvec]  = FUSED ? {v[10], v[11], v[12], v[13]} : {v[6], v[7], v[8], v[9]};
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
        in_mode = vec_ctrl[i][4]; in_conj = vec_ctrl[i][0];
        {in_x_re, in_x_im, in_y_re, in_y_im, in_s_re, in_s_im} = vec_in[i];
        in_tvalid = 1;
      end
      #1 fire = in_tvalid & in_tready; // in_tready only changes on a clock edge or with in_mode
      if (in_tvalid & ~in_tready) stalls = stalls + 1;
      @(posedge clk);
      if (fire) i = i + 1;
    end
    @(negedge clk);
    in_tvalid = 0;
    repeat (REG_STAGES + 4) @(negedge clk);

    if (k != nvec) err = err + 1;
    $display("fpr_butterfly FUSED=%0d REG_STAGES=%0d: checked %0d vectors (%0d out of scope) in %0d cycles (%0d mode-change stalls), %0d errors -> %s",
             FUSED, REG_STAGES, n, skipped, cycles, stalls, err, (err == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
