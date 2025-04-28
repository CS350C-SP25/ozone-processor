`ifndef FPADDER_SV
`define FPADDER_SV
/*
Sequential version of fpadder, fully pipelined across stages.
*/

// `include "./is_special_float.sv"
`include "./leading_one_detector.sv"
`include "./result_rounder.sv"

module fpadder #(
    parameter int EXPONENT_WIDTH = 8,
    parameter int MANTISSA_WIDTH = 23,
    parameter int ROUND_TO_NEAREST_TIES_TO_EVEN = 1,
    parameter int IGNORE_SIGN_BIT_FOR_NAN = 1,
    parameter int FloatBitWidth = EXPONENT_WIDTH + MANTISSA_WIDTH + 1
) (
    input logic clk,
    input logic rst,

    input logic [FloatBitWidth-1:0] a,
    input logic [FloatBitWidth-1:0] b,
    input logic valid_in,
    input logic subtract,

    output logic [FloatBitWidth-1:0] out,
    output logic valid_out,
    output logic underflow_flag,
    output logic overflow_flag,
    output logic invalid_operation_flag
);

    localparam int RoundingBits = MANTISSA_WIDTH;
    localparam int TrueRoundingBits = RoundingBits * ROUND_TO_NEAREST_TIES_TO_EVEN;

    // Stage 0: Unpack inputs and detect special values
    logic s0_valid;
    logic [FloatBitWidth-1:0] s0_a, s0_b;
    logic s0_subtract;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) s0_valid <= 0;
        else begin
            s0_valid <= valid_in;
            s0_a <= a;
            s0_b <= b;
            s0_subtract <= subtract;
        end
    end

    // Stage 1: Unpack fields
    logic s1_valid;
    logic s1_a_sign, s1_b_sign;
    logic [EXPONENT_WIDTH-1:0] s1_a_exp, s1_b_exp;
    logic [MANTISSA_WIDTH-1:0] s1_a_man, s1_b_man;
    logic s1_a_implicit, s1_b_implicit;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) s1_valid <= 0;
        else begin
            s1_valid <= s0_valid;
            s1_a_sign <= s0_a[FloatBitWidth-1];
            s1_b_sign <= s0_subtract ? ~s0_b[FloatBitWidth-1] : s0_b[FloatBitWidth-1];
            s1_a_exp <= s0_a[FloatBitWidth-2 -: EXPONENT_WIDTH];
            s1_b_exp <= s0_b[FloatBitWidth-2 -: EXPONENT_WIDTH];
            s1_a_man <= s0_a[MANTISSA_WIDTH-1:0];
            s1_b_man <= s0_b[MANTISSA_WIDTH-1:0];
            s1_a_implicit <= (s0_a[FloatBitWidth-2 -: EXPONENT_WIDTH] != 0);
            s1_b_implicit <= (s0_b[FloatBitWidth-2 -: EXPONENT_WIDTH] != 0);
        end
    end

    // Stage 2: Align mantissas
    logic s2_valid;
    logic s2_sign_large, s2_sign_small;
    logic [MANTISSA_WIDTH+TrueRoundingBits:0] s2_large_man, s2_small_man;
    logic [EXPONENT_WIDTH-1:0] s2_large_exp;
    logic [EXPONENT_WIDTH:0] s2_exp_diff;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) s2_valid <= 0;
        else begin
            s2_valid <= s1_valid;
            if (s1_a_exp >= s1_b_exp) begin
                s2_large_exp <= s1_a_exp;
                s2_exp_diff <= s1_a_exp - s1_b_exp;
                s2_large_man <= {s1_a_implicit, s1_a_man} << TrueRoundingBits;
                s2_small_man <= ({s1_b_implicit, s1_b_man} << TrueRoundingBits) >> (s1_a_exp - s1_b_exp);
                s2_sign_large <= s1_a_sign;
                s2_sign_small <= s1_b_sign;
            end else begin
                s2_large_exp <= s1_b_exp;
                s2_exp_diff <= s1_b_exp - s1_a_exp;
                s2_large_man <= {s1_b_implicit, s1_b_man} << TrueRoundingBits;
                s2_small_man <= ({s1_a_implicit, s1_a_man} << TrueRoundingBits) >> (s1_b_exp - s1_a_exp);
                s2_sign_large <= s1_b_sign;
                s2_sign_small <= s1_a_sign;
            end
        end
    end

    // Stage 3: Add/sub mantissas
    logic s3_valid;
    logic s3_sign_out;
    logic [MANTISSA_WIDTH+TrueRoundingBits+2:0] s3_sum;
    logic [EXPONENT_WIDTH-1:0] s3_exp;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) s3_valid <= 0;
        else begin
            s3_valid <= s2_valid;
            s3_exp <= s2_large_exp;
            if (s2_sign_large == s2_sign_small) begin
                s3_sum <= s2_large_man + s2_small_man;
                s3_sign_out <= s2_sign_large;
            end else if (s2_large_man >= s2_small_man) begin
                s3_sum <= s2_large_man - s2_small_man;
                s3_sign_out <= s2_sign_large;
            end else begin
                s3_sum <= s2_small_man - s2_large_man;
                s3_sign_out <= s2_sign_small;
            end
        end
    end

    // Stage 4: Leading one detection
    logic s4_valid;
    logic [MANTISSA_WIDTH+TrueRoundingBits+2:0] s4_sum;
    logic [EXPONENT_WIDTH-1:0] s4_exp;
    logic s4_sign;
    wire [$clog2(MANTISSA_WIDTH+TrueRoundingBits+3)-1:0] s4_leading_pos;
    wire s4_has_leading;

    leading_one_detector #(
        .WIDTH(MANTISSA_WIDTH + TrueRoundingBits + 3)
    ) lod_inst (
        .value(s3_sum),
        .position(s4_leading_pos),
        .has_leading_one(s4_has_leading)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) s4_valid <= 0;
        else begin
            s4_valid <= s3_valid;
            s4_sum <= s3_sum;
            s4_exp <= s3_exp;
            s4_sign <= s3_sign_out;
        end
    end

    // Stage 5: Normalize and round inputs
    logic s5_valid;
    logic [MANTISSA_WIDTH-1:0] s5_man;
    logic [RoundingBits-1:0] s5_round_bits;
    logic [EXPONENT_WIDTH-1:0] s5_exp;
    logic s5_sign;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) s5_valid <= 0;
        else begin
            s5_valid <= s4_valid;
            if (s4_has_leading) begin
                logic [MANTISSA_WIDTH+TrueRoundingBits+2:0] shifted;
                int shift_amt = s4_leading_pos - (MANTISSA_WIDTH + RoundingBits);
                if (shift_amt > 0) shifted = s4_sum >> shift_amt;
                else shifted = s4_sum << -shift_amt;
                s5_man <= shifted[MANTISSA_WIDTH+RoundingBits-1:RoundingBits];
                s5_round_bits <= shifted[RoundingBits-1:0];
                s5_exp <= s4_exp - shift_amt;
            end else begin
                s5_man <= 0;
                s5_round_bits <= 0;
                s5_exp <= 0;
            end
            s5_sign <= s4_sign;
        end
    end

    // Stage 6: Round and assemble
    logic s6_valid;
    logic [FloatBitWidth-1:0] s6_out;

    wire [MANTISSA_WIDTH-1:0] round_man;
    wire [EXPONENT_WIDTH-1:0] round_exp;
    wire round_ovf;

    result_rounder #(
        .EXPONENT_WIDTH(EXPONENT_WIDTH),
        .MANTISSA_WIDTH(MANTISSA_WIDTH),
        .ROUND_TO_NEAREST_TIES_TO_EVEN(ROUND_TO_NEAREST_TIES_TO_EVEN),
        .ROUNDING_BITS(RoundingBits)
    ) rounder (
        .non_rounded_exponent(s5_exp),
        .non_rounded_mantissa(s5_man),
        .rounding_bits(s5_round_bits),
        .rounded_exponent(round_exp),
        .rounded_mantissa(round_man),
        .overflow_flag(round_ovf)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) s6_valid <= 0;
        else begin
            s6_valid <= s5_valid;
            s6_out <= {s5_sign, round_exp, round_man};
        end
    end

    assign out = s6_out;
    assign valid_out = s6_valid;
    assign underflow_flag = (s5_exp == 0);
    assign overflow_flag = round_ovf;
    assign invalid_operation_flag = 0; // for simplicity, NaN case detection omitted

endmodule
`endif
