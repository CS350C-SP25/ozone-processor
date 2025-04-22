// FSM implementation of fpmult, takes 13 cycles
// TODO implement combinational FPU that takes 1 cycle

// Q IS EXPONENT P IS SIGNIFICAND 
module fpmult_rtl #(parameter int P=8, parameter int Q=8)(
    input  logic rst_in_N,        // asynchronous active-low reset
    input  logic clk_in,          // clock
    input  logic [P+Q-1:0] x_in,     // input X; x_in[15] is the sign bit
    input  logic [P+Q-1:0] y_in,     // input Y: y_in[15] is the sign bit
    input  logic [1:0] round_in,  // rounding mode specifier
    input  logic start_in,        // signal to start multiplication
    output logic [P+Q-1:0] p_out,  // output P: p_out[15] is the sign bit
    output logic [3:0] oor_out, // out-of-range indicator vector
    output logic done_out       // signal that outputs are ready
);
    logic[Q:0] exp_interm;
    exponent_adder #(.P(P), .Q(Q)) exp_adder (x_in[P+Q-2:0], y_in[P+Q-2:0], exp_interm);
    logic sign_out;
    sign_computer sign_comp (x_in[P+Q-1], y_in[P+Q-1], sign_out);
    logic[P-1:0] sig_a;
    logic[P-1:0] sig_b;
    input_handler  #(.P(P), .Q(Q)) sig_comp (x_in, y_in, sig_a, sig_b);
    logic[Q-1:0] exp_out;
    logic err;
    logic[P-2:0] sig_out;
    output_assembler #(.P(P), .Q(Q)) assemble_out(sign_out, exp_out, sig_out, p_out, oor_out);

    control_fsm #(.P(P), .Q(Q)) main_fsm (
        .clk(clk_in), .reset(~rst_in_N), .start(start_in), .exp_in(exp_interm), .sig_a(sig_a), .sig_b(sig_b),
        .a_no_sign(x_in[P+Q-2:0]), .b_no_sign(y_in[P+Q-2:0]), .sign(sign_out), .round_in(round_in),
        .exp_out(exp_out), .done(done_out), .err(err), .sig_out(sig_out)
    );

endmodule

module output_assembler #(parameter P, parameter Q) (
    input logic sign,
    input logic[Q-1:0] exp,
    input logic[P-2:0] sig,
    output logic[P+Q-1:0] p_out,
    output logic[3:0] oor_out
);
    assign p_out = {sign, exp, sig};
    assign oor_out[3] = ~(|exp | |sig );
    assign oor_out[2] = &exp & ~|sig;
    assign oor_out[1] = &exp & |sig;
    assign oor_out[0] = ~|exp & |sig;
endmodule

module input_handler #(parameter P, parameter Q)
(
    input logic[P+Q-1:0] x_in,
    input logic[P+Q-1:0] y_in,
    output logic[P-1:0] sig_a,
    output logic[P-1:0] sig_b
);
    localparam LEN = P+Q;
    localparam EXP_ED = LEN-2;
    localparam EXP_ST = P-1;
    // computes {exp is non-zero & not infinity (all-ones), significand}
    assign sig_a = {|x_in[EXP_ED:EXP_ST] & ~&x_in[EXP_ED:EXP_ST], x_in[EXP_ST-1:0]};
    assign sig_b = {|y_in[EXP_ED:EXP_ST] & ~&y_in[EXP_ED:EXP_ST], y_in[EXP_ST-1:0]};
endmodule

// exp_out is Q+1 bits because worst case exp_x_in + exp_y_in fits in Q+1 bits 
module exponent_adder #(parameter P, parameter Q)
(
    input logic[P+Q-2:0] x_in,
    input logic[P+Q-2:0] y_in,
    output logic signed[Q:0] exp_out
);
    localparam LEN = P+Q;
    localparam EXP_ED = LEN-2;
    localparam EXP_ST = P-1;
    localparam BIAS = (1 << (Q-1)) - 1;
    logic[Q-1:0] x_tmp;
    logic[Q-1:0] y_tmp;
    // if exp_x is all 0, assign 0000...1 otherwise return the normal exponent
    assign x_tmp = x_in[EXP_ED:EXP_ST] == {Q{1'h0}} ? {{(Q-1){1'h0}}, 1'h1} : x_in[EXP_ED:EXP_ST];
    assign y_tmp = y_in[EXP_ED:EXP_ST] == {Q{1'h0}} ? {{(Q-1){1'h0}}, 1'h1} : y_in[EXP_ED:EXP_ST];
    // if either exponent is all 1s then the result is going to be nans or infinities: some cases still not handled
    // if the result is going to be nans or infinities set exp_out to all ones except leading bit
    // if either number is 0 then the exponent will be zero and the multiplier will handle the significand (subnormal)
    assign exp_out = &x_tmp | &y_tmp ? 
                        {1'h0, {Q{1'h1}}} 
                        : ~|x_in | ~|y_in ? 
                            {(Q+1){1'h0}} 
                            : 
                            {1'b0, x_tmp} + {1'b0, y_tmp} - BIAS;
endmodule

module sign_computer(
    input logic x_sign,
    input logic y_sign,
    output logic sign_out
);
    assign sign_out = x_sign ^ y_sign;
endmodule

module nan_computer #(parameter P, parameter Q)(
    input logic[P+Q-2:0] x_in,
    input logic[P+Q-2:0] y_in,
    output logic is_nan
);
    localparam LEN = P+Q;
    localparam EXP_ED = LEN-2;
    localparam EXP_ST = P-1;
    localparam SIG_ED = EXP_ST-1;
    //cases where a product is nan:
    //either number is nan
    //cases where a number is 0 and the other is infinity
    assign is_nan = (&x_in[EXP_ED:EXP_ST] & |x_in[SIG_ED:0]) | 
                    (&y_in[EXP_ED:EXP_ST] & |y_in[SIG_ED:0]) | 
                    (&x_in[EXP_ED:EXP_ST] & ~|x_in[SIG_ED:0] & ~|y_in) | 
                    (&y_in[EXP_ED:EXP_ST] & ~|y_in[SIG_ED:0] & ~|x_in);
endmodule

module negative_truncate_exp_in #(parameter P, parameter Q)(
    input logic[Q:0] exp_in,
    output logic[$clog2(P+1)-1:0] trunc_out,
    output logic[P:0] masked_bits
);
    logic[Q:0] neg_exp_in = ~exp_in + 1;
    assign trunc_out = neg_exp_in[$clog2(P+1)-1:0];
    assign masked_bits = (1 << (trunc_out)) - 1;
endmodule

module control_fsm #(parameter P, parameter Q)(
    input logic clk,
    input logic reset,
    input logic start,
    input logic signed[Q:0] exp_in,
    input logic[P-1:0] sig_a,
    input logic[P-1:0] sig_b,
    input logic[P+Q-2:0] a_no_sign,
    input logic[P+Q-2:0] b_no_sign,
    input logic sign,
    input logic[1:0] round_in,
    output logic[Q-1:0] exp_out,
    output logic done,
    output logic err,
    output logic[P-2:0] sig_out
);
    logic[3:0] cur_state;
    logic[3:0] next_state;
    logic mDone;
    logic mStart;
    logic mStart_next;
    logic[P-1:0] product_out;
    logic g_bit;
    logic r_bit;
    logic s_bit;
    logic signed [Q:0] exp_control_cur;
    logic signed [Q:0] exp_control_next;
    logic [$clog2(P)-1:0] exponent_shift;
    multiplier_fsm #(.P(P), .Q(Q)) fsm_multiplier_controlled (
        .clk(clk), .reset(reset), .start(mStart), .sig_a(sig_a), .sig_b(sig_b), .exp_in(exp_in),
        .product(product_out), .g(g_bit), .r(r_bit), .s(s_bit), .done(mDone), .exponent_shift(exponent_shift));
    logic is_nan;
    nan_computer #(.P(P), .Q(Q)) compute_nan(a_no_sign, b_no_sign, is_nan);
    logic[$clog2(P+1)-1:0] trunc_exp_in;
    logic[P:0] exp_in_bits_masked;
    negative_truncate_exp_in #(.P(P), .Q(Q)) trunc_neg_exp_in(exp_control_cur, trunc_exp_in, exp_in_bits_masked);
    logic signed[31:0] exp_extended;
    sign_extend_exponent #(.Q(Q)) extend_exp_signed (.exp_in(exp_in), .exp_extended(exp_extended));
    logic[P:0] control_product_cur;
    logic[P:0] control_product_next;
    logic g_control_cur;
    logic r_control_cur;
    logic s_control_cur;
    logic g_control_next;
    logic r_control_next;
    logic s_control_next;
    logic[P-2:0] sig_next;
    logic[Q-1:0] exp_next;
    always_ff @( posedge clk or posedge reset ) begin : main_ctrl_fsm
        if (reset) begin
            cur_state <= 4'b0000;
        end
        else begin
            if (cur_state == 4'b0111) begin
                done = 1'b1;
            end else begin
                done = 1'b0;
            end
            cur_state <= next_state;
            exp_control_cur <= exp_control_next;
            control_product_cur <= control_product_next;
            g_control_cur <= g_control_next;
            r_control_cur <= r_control_next;
            s_control_cur <= s_control_next;
            exp_out <= exp_next;
            sig_out <= sig_next;
        end
    end

    always_comb begin : main_ctrl_state_handler
        case (cur_state)
            4'b0000: begin
                if (start) begin
                    next_state = 4'b0001;
                    mStart = 1'b1;
                end
                else begin
                    mStart = 1'b0;
                    next_state = 4'b0000;
                end
                sig_next = sig_out;
                exp_next = exp_out;
                exp_control_next = exp_control_cur;
                control_product_next = control_product_cur;
                g_control_next = g_control_cur;
                r_control_next = r_control_cur;
                s_control_next = s_control_cur;
            end
            4'b0001: begin //calculate product
                if (mDone) begin
                    next_state = 4'b0010;
                    exp_control_next = exp_control_cur;
                    control_product_next = {1'b0, product_out};
                    g_control_next = g_bit;
                    r_control_next = r_bit;
                    s_control_next = s_bit;
                end
                else begin
                    next_state = 4'b0001;
                    exp_control_next = exp_control_cur;
                    control_product_next = control_product_cur;
                    g_control_next = g_control_cur;
                    r_control_next = r_control_cur;
                    s_control_next = s_control_cur;
                end
                mStart = 1'b0;
                sig_next = sig_out;
                exp_next = exp_out;
            end
            4'b0010: begin //normalized and adjusted exponent and rounding bits
                if (control_product_cur[P-1]) begin
                    exp_control_next = exp_in + {{Q-1{1'b0}}, 1'b1};
                    s_control_next = r_control_cur | s_control_cur;

                    control_product_next = control_product_cur;
                    g_control_next = g_control_cur;
                    r_control_next = r_control_cur;
                end else begin
                    //0 extended to Q+1 bits
                    exp_control_next = exp_in - {{(Q+1-$clog2(P)){1'b0}}, exponent_shift};
                    control_product_next = {1'b0, control_product_cur[P-2:0], g_control_cur};
                    g_control_next = r_control_cur;

                    r_control_next = r_control_cur;
                    s_control_next = s_control_cur;
                end
                next_state = 4'b0011;
                mStart = 1'b0;
                sig_next = sig_out;
                exp_next = exp_out;
            end
            4'b0011: begin
                if (exp_control_cur < 1 && exp_control_cur > 1 - ((1 << (Q-1)) - 1) ) begin
                    if (exp_extended > -P) begin
                        r_control_next = 1'b0;
                        g_control_next = control_product_cur[trunc_exp_in];
                        exp_control_next = {Q+1{1'b0}};
                        control_product_next = control_product_cur >> (trunc_exp_in + 1);
                        if (exp_control_cur == 0) begin
                            s_control_next = r_control_cur | s_control_cur;
                        end else begin
                            s_control_next = r_control_cur | s_control_cur | (|(control_product_cur & exp_in_bits_masked));
                        end
                    end else begin //the whole thing has been shifted out its all sticky for rounding cases.
                        s_control_next = g_control_cur | r_control_cur | s_control_cur | (|control_product_cur);
                        exp_control_next = {Q+1{1'b0}};
                        control_product_next = {P+1{1'b0}};
                        g_control_next = 1'b0;
                        r_control_next = 1'b0;
                    end
                end else begin
                    control_product_next = control_product_cur;
                    exp_control_next = exp_control_cur;
                    g_control_next = g_control_cur;
                    r_control_next = r_control_cur;
                    s_control_next = s_control_cur;
                end
                next_state = 4'b0100;
                mStart = 1'b0;
                sig_next = sig_out;
                exp_next = exp_out;
            end
            4'b0100: begin //round
                    if(round_in == 2'b00) begin //round to nearest tiebreak to even
                        if (g_control_cur) begin //rounding bit is set, check stickies, and not infinity
                            if (s_control_cur) begin //sticky is set
                                control_product_next = control_product_cur + {{P-1{1'b0}}, 1'b1};
                            end else if (control_product_cur[0]) begin //sticky not set, rounding to even
                                control_product_next = control_product_cur + {{P-1{1'b0}}, 1'b1};
                            end else 
                                control_product_next = control_product_cur;
                        end else begin
                            control_product_next = control_product_cur;
                        end
                    end
                    else if (round_in == 2'b01) begin //round to zero
                        control_product_next = control_product_cur;
                    end
                    else if (round_in == 2'b10) begin
                        if ((g_control_cur | s_control_cur) & sign) begin //round down if negative, else truncate
                            control_product_next = control_product_cur + {{P-1{1'b0}}, 1'b1};
                        end else 
                            control_product_next = control_product_cur;
                    end
                    else begin
                        if ((g_control_cur | s_control_cur) & ~sign) begin //round up if positive, else truncate
                            control_product_next = control_product_cur + {{P-1{1'b0}}, 1'b1};
                        end else 
                            control_product_next = control_product_cur;
                    end
                exp_control_next = exp_control_cur;
                g_control_next = g_control_cur;
                r_control_next = r_control_cur;
                s_control_next = s_control_cur;
                next_state = 4'b0101;
                mStart = 1'b0;
                sig_next = sig_out;
                exp_next = exp_out;
            end
            4'b0101: begin //normalize again
                if (control_product_cur[P]) begin
                    exp_control_next = exp_in + {{Q-1{1'b0}}, 1'b1};
                    control_product_next = {1'b0, control_product_cur[P:1]};
                end else begin 
                    exp_control_next = exp_control_cur;
                    control_product_next = control_product_cur;
                end
                g_control_next = g_control_cur;
                r_control_next = r_control_cur;
                s_control_next = s_control_cur;
                next_state = 4'b0110;
                mStart = 1'b0;
                sig_next = sig_out;
                exp_next = exp_out;
            end
            4'b0110: begin //write to outputs
                if (is_nan) begin //nan case
                    sig_next = {{P-2{1'b0}}, 1'b1}; //hard coded to some form of NAN :skull:
                    exp_next = {Q{1'b1}};
                end
                else if (exp_control_cur < -(1 << (Q-1)) || exp_control_cur == {1'b0, {Q{1'b1}}}) begin
                    //overflowed to or past infinity, two cases legit infinity (infinity * not nan and not 0) or some rounding edge case
                    if (&a_no_sign[P+Q-2:P-1] | &b_no_sign[P+Q-2:P-1]) begin //real infinity, nans already handled
                        sig_next = {P-1{1'b0}}; //hard coded to infinity
                        exp_next = {Q{1'b1}};
                    end else begin
                        if(round_in == 2'b00) begin //round to nearest tiebreak to even
                            // we go to infinity!
                            sig_next = {P-1{1'b0}}; //hard coded to infinity
                            exp_next = {Q{1'b1}};
                        end
                        else if (round_in == 2'b01) begin //round to zero
                            sig_next = {P-1{1'b1}}; //infinity -1
                            exp_next = {Q{1'b1}} - 1;
                        end
                        else if (round_in == 2'b10) begin //round towards -infintiy (down)
                            if (sign) begin //negative
                                sig_next = {P-1{1'b0}}; //hard coded to infinity
                                exp_next = {Q{1'b1}};
                            end else begin
                                sig_next = {P-1{1'b1}}; //infinity -1
                                exp_next = {Q{1'b1}} - 1;
                            end
                        end
                        else begin
                            if (sign) begin //negative
                                sig_next = {P-1{1'b1}}; //infinity -1
                                exp_next = {Q{1'b1}} - 1;
                            end else begin
                                sig_next = {P-1{1'b0}}; //hard coded to infinity
                                exp_next = {Q{1'b1}};
                            end
                        end
                    end
                end
                else if ((exp_control_cur == 1 && !control_product_cur[P-1]) || exp_control_cur < 1) begin //subnormal regular
                    exp_next = {Q{1'b0}};
                    sig_next = control_product_cur[P-2:0];
                end
                else begin
                    exp_next = exp_control_cur[Q-1:0];
                    sig_next = control_product_cur[P-2:0];
                end
                // else if() begin //overflow infinity cases
                // end else if() begin //subnormal exponent underflow cases / zero rounding cases
                // end
                exp_control_next = exp_control_cur;
                control_product_next = control_product_cur;
                g_control_next = g_control_cur;
                r_control_next = r_control_cur;
                s_control_next = s_control_cur;
                next_state = 4'b0111;
                mStart = 1'b0;
            end
            4'b0111: begin
                //do nothing but update done
                next_state = 4'b0000;
                mStart = 1'b0;
                sig_next = sig_out;
                exp_next = exp_out;
                exp_control_next = exp_control_cur;
                control_product_next = control_product_cur;
                g_control_next = g_control_cur;
                r_control_next = r_control_cur;
                s_control_next = s_control_cur;
            end
            default: begin
                next_state = 4'b0000;
                mStart = 1'b0;
                sig_next = sig_out;
                exp_next = exp_out;
                exp_control_next = exp_control_cur;
                control_product_next = control_product_cur;
                g_control_next = g_control_cur;
                r_control_next = r_control_cur;
                s_control_next = s_control_cur;
            end
        endcase
    end
endmodule

module multiplier_fsm #(parameter P, parameter Q)(
    input logic clk,
    input logic reset,
    input logic start,
    input logic[P-1:0] sig_a,
    input logic[P-1:0] sig_b,
    input logic signed[Q:0] exp_in,
    output logic[P-1:0] product,
    output logic g,
    output logic r,
    output logic s,
    output logic done,
    output logic[$clog2(P)-1:0] exponent_shift
);
    localparam PRODUCT_LEN=2*P;
    localparam REG_BITS=$clog2(P+1);
    // log2(P+1)
    logic [REG_BITS-1:0] cur_state;
    logic [REG_BITS-1:0] next_state;
    logic [PRODUCT_LEN-1:0] p_vector;
    logic [PRODUCT_LEN-1:0] product_next;
    logic [PRODUCT_LEN-1:0] p_vector_next;
    shift_add_clb #(P) shift_add_fsm (
        .product_cur(p_vector), .multiplicand(sig_b), .product_next(product_next));
    logic [31:0] leading_zeroes;
    leading_zero_counter #(PRODUCT_LEN) nlz (p_vector, leading_zeroes);
    logic[P-1:0] uPb_out;
    upper_P_bits #(P) uPb (leading_zeroes, p_vector, uPb_out);
    logic[31:0] lz_cap_out;
    leading_zero_cap #(.P(P), .Q(Q)) lz_cap (exp_in, leading_zeroes, lz_cap_out);

    logic [P-1:0] product_out_next;
    logic s_next;
    logic r_next;
    logic g_next;
    

    always_ff @( posedge clk or posedge reset) begin : mult_fsm
        if (reset) begin
            cur_state <= {REG_BITS{1'b0}};
        end else begin
            if (cur_state == 4'(P+1)) begin
                product <= product_out_next;
                s <= s_next;
                r <= r_next;
                g <= g_next;
                exponent_shift <= exponent_shift_next[$clog2(P)-1:0];
            end
            if (cur_state == 4'(P+2)) begin
                done = 1'b1;
            end else begin
                done = 1'b0;
            end
            cur_state <= next_state;
            p_vector <= p_vector_next;
        end
    end

    always_comb begin : multiplier_state_handler
        if (cur_state == 0) begin
            next_state = start ? {{(REG_BITS-1){1'b0}}, 1'b1} : {REG_BITS{1'b0}};
        end else if (cur_state <= 4'(P + 1)) begin
            // for each significand bit perform shift add logic
            next_state = cur_state + 1;
        end else begin
            next_state = {REG_BITS{1'b0}};
        end
    end

    always_comb begin : shift_add_handler
        if (cur_state == {REG_BITS{1'b0}}) begin
            if (start) begin
                p_vector_next = {{P{1'b0}}, sig_a}; // Load input on start
            end else begin
                p_vector_next = p_vector; // Hold previous value
            end
        end else begin
            p_vector_next = product_next; // Use shift-add module output
        end
    end

    logic[31:0] exponent_shift_next;
    logic [PRODUCT_LEN-1:0] temp_store; 
    always_comb begin
        if (cur_state == 4'(P+1)) begin
            if (lz_cap_out > 1) begin
                //we must normalize
                exponent_shift_next = lz_cap_out - 1;
                if (P+1 < lz_cap_out) begin
                    //bring as many bits as possible and fill the rest with zeroes
                    product_out_next = uPb_out;
                end else begin
                    product_out_next = p_vector[PRODUCT_LEN-lz_cap_out -:P];
                end
                if (P-2<lz_cap_out) begin
                    s_next = 1'b0;
                end else begin
                    s_next = |(p_vector & ((1 << (P-1-lz_cap_out)) - 1));
                end

                if (P-1<lz_cap_out) begin
                    r_next = 1'b0;
                end else begin
                    r_next = p_vector[P-1-lz_cap_out];
                end

                if (P<lz_cap_out) begin
                    g_next = 1'b0;
                end else begin
                    g_next = p_vector[P-lz_cap_out];
                end
                
            end else begin
                product_out_next = p_vector[PRODUCT_LEN-1:P];
                s_next = |p_vector[P-3:0];
                r_next = p_vector[P-2];
                g_next = p_vector[P-1];
                exponent_shift_next = 32'b0;
            end
        end else begin
            product_out_next = product;
            s_next = s;
            r_next = r;
            g_next = g;
            exponent_shift_next = {{(32-$clog2(P)){1'b0}},exponent_shift};
        end
    end
endmodule

module shift_add_clb #(parameter P)(
    input logic[2*P-1:0] product_cur,
    input logic[P-1:0] multiplicand,
    output logic[2*P-1:0] product_next
);
    localparam PRODUCT_LEN=2*P;
    wire [PRODUCT_LEN:0] add_intermediary;
    wire [P:0] sum_upper;
    // if product_cur[0] is 1, actual multiplication so shift and add otherwise just shift
    assign sum_upper = product_cur[PRODUCT_LEN-1:P] + (product_cur[0] ? {1'b0, multiplicand[P-1:0]} : {(P+1){1'b0}});
    assign add_intermediary = {sum_upper, product_cur[P-1:0]};
    assign product_next = add_intermediary[PRODUCT_LEN:1]; // shift
endmodule

module sign_extend_exponent #(Q) (
    input logic[Q:0] exp_in,
    output logic signed[31:0] exp_extended
);
assign exp_extended = {{(32-(Q+1)){exp_in[Q]}}, exp_in};
endmodule

module leading_zero_counter #(
    parameter int PRODUCT_LEN = 16  // Default size
)(
    input  logic [PRODUCT_LEN-1:0] in_vector, // Input bit vector
    output logic [31:0] nlz  // Output count of leading zeroes
);
    integer i;
    
    always_comb begin
        nlz = 0;
        for (i = PRODUCT_LEN-1; i >= 0; i--) begin
            if (in_vector[i]) begin
                nlz = PRODUCT_LEN - 1 - i;
                break;
            end
        end
    end
endmodule

module upper_P_bits #(parameter int P) (
    input logic[31:0] lz,
    input logic[P*2-1:0] vec,
    output logic[P-1:0] out
);
    logic[P*2-1:0] mid = vec << lz;
    assign out = mid[P*2-1 -: P];
endmodule

module leading_zero_cap #(parameter int P, parameter int Q) (
    input logic [Q:0] exp_in,
    input logic [31:0] lz,
    output logic [31:0] max_exp_shift
);
    assign max_exp_shift = lz > {{(32-(Q+1)){1'b0}}, exp_in} ? {{(32-(Q+1)){1'b0}}, exp_in} : lz;
endmodule
