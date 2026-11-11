`timescale 1ns/1ps
module lo_check_tb;
  reg  [63:0] din; wire [5:0] dout;
  integer p, k, err = 0, n = 0, expected;
  leading_one_calc #(.N(64), .N_BITS(6)) dut (.loc_din(din), .loc_dout(dout));
  function integer ref_loc(input [63:0] x); integer i; begin ref_loc = 0; for (i=0;i<64;i=i+1) if (x[i]) ref_loc = i; end endfunction
  task check; begin
    #1; n = n + 1; expected = ref_loc(din);
    if (dout !== expected[5:0]) begin err = err + 1; if (err < 10) $display("FAIL din=%h got=%0d exp=%0d", din, dout, expected); end
  end endtask
  initial begin
    for (p = 0; p < 64; p = p + 1) begin
      din = 64'd1 << p; check;                         // single bit
      din = (64'd1 << p) | ((64'd1 << p) - 1); check;  // all ones below
      for (k = 0; k < 2000; k = k + 1) begin           // random bits below
        din = (64'd1 << p) | ({$random, $random} & ((64'd1 << p) - 1)); check;
      end
    end
    din = 64'hFFFF_FFFF_FFFF_FFFF; check;
    $display("leading_one_calc: %0d vectors, %0d errors", n, err);
    $finish;
  end
endmodule
