import uop_pkg::*;
import reg_pkg::*;
import is_pkg::*;
import rob_pkg::*;

module is_queue #(
    parameter N = IS_ENTRIES
) (
    input logic rst_N_in,
    input logic clk_in,
    input logic flush_in
    // TODO ...
);
    // instruction scheduler queue
    is_entry [N-1:0] q;
    logic [$clog2(N)-1:0] is_head;
    logic [$clog2(N)-1:0] is_tail;

endmodule

// module ready_queue #(
//     parameter N = RQ_ENTRIES
// ) (
//     input logic rst_N_in,
//     input logic clk_in,
//     input logic flush_in
// );
//     // ready queue
//     rq_entry [N-1:0] q;
//     logic [$clog2(N)-1:0] rq_head;
//     logic [$clog2(N)-1:0] rq_tail;

// endmodule


module instruction_scheduler #(
    parameter Q_DEPTH = is_pkg::IS_ENTRIES,
    parameter Q_WIDTH = uop_pkg::INSTR_Q_WIDTH
) (
    input logic clk_in,
    input logic rst_N_in,
    input logic flush_in,

    // instructions from the ROB
    input rob_issue lsu_insn_in,
    input rob_issue bru_insn_in, 
    input rob_issue alu_insn_in, 
    input rob_issue fpu_insn_in,

    // ready signals from the func units
    input logic lsu_ready_in,
    input logic bru_ready_in,
    input logic alu_ready_in,
    input logic fpu_ready_in,
    
    // TODO: data the func units will take in
    // output __ lsu_input_out,
    output logic lsu_valid_out,
    // output __ bru_input_out,
    output logic bru_valid_out,
    // output __ alu_input_out,
    output logic alu_valid_out,
    // output __ fpu_input_out,
    output logic fpu_valid_out,

    // signal the ROB which instructions have been accepted by the func units
    output logic lsu_insn_executing_out,
    output logic bru_insn_executing_out,
    output logic alu_insn_executing_out,
    output logic fpu_insn_executing_out
);

    // TODO: parameterize # of functional units

    // asymmetric # of units per FU type

    
    // 4 queues (1 per FU)
    rob_issue queue[NUM_OF_FU][Q_DEPTH];
    logic [$clog2(Q_DEPTH):0] head[4], tail[4];
    logic [$clog2(Q_DEPTH+1):0] count[4];

    rob_issue [NUM_OF_FU-1:0] insn_in;

    assign insn_in[0] = lsu_insn_in;
    assign insn_in[1] = bru_insn_in;
    assign insn_in[2] = alu_insn_in;
    assign insn_in[3] = fpu_insn_in;

    logic [NUM_OF_FU-1:0] ready_in;
    assign ready_in = {fpu_ready_in, alu_ready_in, bru_ready_in, lsu_ready_in};

    logic [NUM_OF_FU-1:0] executing_out;
    
    always_ff @(posedge clk_in) begin
        if (!rst_N_in || flush_in) begin
            for (int i = 0; i < 4; i++) begin
                head[i] <= 0;
                tail[i] <= 0;
                count[i] <= 0;
            end
            lsu_insn_executing_out <= 0;
            bru_insn_executing_out <= 0;
            alu_insn_executing_out <= 0;
            fpu_insn_executing_out <= 0;
        end else begin
            // ROB input handling, enqueue instructions 
            for (int j = 0; j < NUM_OF_FU; j++) begin
                if (insn_in[j].valid && count[j] < QUEUE_DEPTH) begin // TODO: maybe a valid bit in rob_issue? 
                    queue[j][tail[j]] <= insn_in[j];
                    tail[j] <= tail[j] + 1;
                    count[j] <= count[j] + 1;
                end
            end

            // FU output handling, dequeue instructions 
            for (int j = 0; j < NUM_OF_FU; j++) begin
                if (ready_in[j] && count[j] > 0) begin
                    // TODO: give data and set valid bit
                    head[j] <= head[j] + 1;
                    count[j] <= count[j] - 1;
                    executing_out[j] <= 1;
                end
            end

            lsu_insn_executing_out <= executing_out[0];
            bru_insn_executing_out <= executing_out[1];
            alu_insn_executing_out <= executing_out[2];
            fpu_insn_executing_out <= executing_out[3];
        end
    end
    
    // // Instruction scheduler queue
    // is_queue #(.N(IS_ENTRIES)) iq (.rst_N_in(rst_N_in), .clk_in(clk_in), .flush_in(flush_in));
    
endmodule;
