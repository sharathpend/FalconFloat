
`include "defines.vh"

// Normalize the mantissa after addition
module fpr_add_norm (
    input  wire        in1_sign,
    input  wire        in2_sign,
    input  wire [53:0] result_mant_add,
    input  wire [53:0] result_mant_sub,
    input  wire [10:0] result_exp,
    
    input  wire        shifted_mantissa_g,
    input  wire        shifted_mantissa_r,
    input  wire        shifted_mantissa_s,

    output wire [52:0] final_mant,
    output wire [10:0] final_exp
);
    
    `ifdef FPGA_DESIGN
        reg  [52:0] mant_add_path = 0;
        reg  [52:0] mant_sub_path = 0;
        reg  [10:0] exp_add_path = 0;
        reg  [10:0] exp_sub_path = 0;
        reg         round_up = 0;
        reg  [5:0]  shift_amount = 0; // For the subtraction path, can shift from 0 to 53 positions
    `else
        reg  [52:0] mant_add_path;
        reg  [52:0] mant_sub_path;
        reg  [10:0] exp_add_path;
        reg  [10:0] exp_sub_path;
        reg         round_up;
        reg  [5:0]  shift_amount; // For the subtraction path, can shift from 0 to 53 positions
    `endif

    // This single combinatorial block calculates the result for both cases
    always @(*) begin
        // signs are the same (effective addition)
        if (result_mant_add[53]) begin
            // Overflow occurred. I think this does not account for overflow
            // after roundup.
            round_up = result_mant_add[0] & result_mant_add[1]; // If G=1 and LSB=1 (50% and odd, round up)
            mant_add_path = result_mant_add[53:1] + round_up;
            exp_add_path = result_exp + 1;
        end else begin
            // No overflow
            mant_add_path = result_mant_add[52:0];
            exp_add_path = result_exp;
        end

        // signs are different (effective subtraction)
        if      (result_mant_sub[52]) shift_amount = 0;
        else if (result_mant_sub[51]) shift_amount = 1;
        else if (result_mant_sub[50]) shift_amount = 2;
        else if (result_mant_sub[49]) shift_amount = 3;
        else if (result_mant_sub[48]) shift_amount = 4;
        else if (result_mant_sub[47]) shift_amount = 5;
        else if (result_mant_sub[46]) shift_amount = 6;
        else if (result_mant_sub[45]) shift_amount = 7;
        else if (result_mant_sub[44]) shift_amount = 8;
        else if (result_mant_sub[43]) shift_amount = 9;
        else if (result_mant_sub[42]) shift_amount = 10;
        else if (result_mant_sub[41]) shift_amount = 11;
        else if (result_mant_sub[40]) shift_amount = 12;
        else if (result_mant_sub[39]) shift_amount = 13;
        else if (result_mant_sub[38]) shift_amount = 14;
        else if (result_mant_sub[37]) shift_amount = 15;
        else if (result_mant_sub[36]) shift_amount = 16;
        else if (result_mant_sub[35]) shift_amount = 17;
        else if (result_mant_sub[34]) shift_amount = 18;
        else if (result_mant_sub[33]) shift_amount = 19;
        else if (result_mant_sub[32]) shift_amount = 20;
        else if (result_mant_sub[31]) shift_amount = 21;
        else if (result_mant_sub[30]) shift_amount = 22;
        else if (result_mant_sub[29]) shift_amount = 23;
        else if (result_mant_sub[28]) shift_amount = 24;
        else if (result_mant_sub[27]) shift_amount = 25;
        else if (result_mant_sub[26]) shift_amount = 26;
        else if (result_mant_sub[25]) shift_amount = 27;
        else if (result_mant_sub[24]) shift_amount = 28;
        else if (result_mant_sub[23]) shift_amount = 29;
        else if (result_mant_sub[22]) shift_amount = 30;
        else if (result_mant_sub[21]) shift_amount = 31;
        else if (result_mant_sub[20]) shift_amount = 32;
        else if (result_mant_sub[19]) shift_amount = 33;
        else if (result_mant_sub[18]) shift_amount = 34;
        else if (result_mant_sub[17]) shift_amount = 35;
        else if (result_mant_sub[16]) shift_amount = 36;
        else if (result_mant_sub[15]) shift_amount = 37;
        else if (result_mant_sub[14]) shift_amount = 38;
        else if (result_mant_sub[13]) shift_amount = 39;
        else if (result_mant_sub[12]) shift_amount = 40;
        else if (result_mant_sub[11]) shift_amount = 41;
        else if (result_mant_sub[10]) shift_amount = 42;
        else if (result_mant_sub[9])  shift_amount = 43;
        else if (result_mant_sub[8])  shift_amount = 44;
        else if (result_mant_sub[7])  shift_amount = 45;
        else if (result_mant_sub[6])  shift_amount = 46;
        else if (result_mant_sub[5])  shift_amount = 47;
        else if (result_mant_sub[4])  shift_amount = 48;
        else if (result_mant_sub[3])  shift_amount = 49;
        else if (result_mant_sub[2])  shift_amount = 50;
        else if (result_mant_sub[1])  shift_amount = 51;
        else if (result_mant_sub[0])  shift_amount = 52;
        else                          shift_amount = 53; // result is true zero

        // Perform the left shift and exponent adjustment using the calculated shift amount
        mant_sub_path = result_mant_sub[52:0] << shift_amount;
        exp_sub_path = result_exp - shift_amount;

        // Handle the special case where the result is a true zero
        if (shift_amount == 53) begin
            exp_sub_path = 11'b0; // For a zero result, the exponent must also be zero
        end
    end

    assign final_mant = (in1_sign == in2_sign) ? mant_add_path : mant_sub_path;
    assign final_exp  = (in1_sign == in2_sign) ? exp_add_path : exp_sub_path;

endmodule