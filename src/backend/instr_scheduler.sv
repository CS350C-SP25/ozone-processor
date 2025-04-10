import uop_pkg::*;
import reg_pkg::*;
import is_pkg::*;
import rob_pkg::*;

module fu_queue #(
    parameter Q_DEPTH = is_pkg::FQ_ENTRIES,
    parameter Q_WIDTH = is_pkg::FQ_EL_SIZE
) (
    input logic clk,
    input logic rst,
    input logic flush,

    // enqueue
    input logic enq_valid, // getting the request to enqueue
    input logic [Q_WIDTH-1:0] enq_data,

    // dequeue
    input logic deq_ready,  // getting the request to dequeue
    output logic deq_valid, // deq_data holds valid dequeued data
    output logic [Q_WIDTH-1:0] deq_data,

    output logic full
);
    logic [Q_WIDTH-1:0] q [Q_DEPTH-1:0];
    logic [$clog2(Q_DEPTH)-1:0] head, tail;
    logic [$clog2(Q_DEPTH+1)-1:0] count;
    logic empty;
    
    assign full  = (count == Q_DEPTH);
    assign empty = (count == 0);
    assign deq_valid = !empty;
    assign deq_data = q[head];

    always_ff @(posedge clk) begin
        if (!rst || flush) begin
            head  <= 0;
            tail  <= 0;
            count <= 0;
        end else begin
            // enqueue
            if (enq_valid && !full) begin
                q[tail] <= enq_data;
                tail <= (tail + 1) % Q_DEPTH;
                count <= count + 1;
            end

            // dequeue
            if (deq_ready && !empty) begin
                head <= (head + 1) % Q_DEPTH;
                count <= count - 1;
            end
        end
    end

endmodule


module instruction_scheduler #(
    parameter Q_DEPTH = is_pkg::FQ_ENTRIES,
    parameter Q_WIDTH = is_pkg::FQ_EL_SIZE
) (
    input logic clk_in,
    input logic rst_N_in,
    input logic flush_in,

    // instructions from the ROB
    input rob_issue lsu_insn_i,
    input rob_issue bru_insn_in, 
    input rob_issue alu_insn_in, 
    input rob_issue fpu_insn_in,

    // ready signals from the func units
    input logic lsu_ready_in [is_pkg::NUM_LSU],
    input logic bru_ready_in [is_pkg::NUM_BRU],
    input logic alu_ready_in [is_pkg::NUM_ALU],
    input logic fpu_ready_in [is_pkg::NUM_FPU],
    
    // data the func units will take in
    output uop_insn lsu_input_out [is_pkg::NUM_LSU],
    output logic lsu_valid_out [is_pkg::NUM_LSU],

    output uop_insn bru_input_out [is_pkg::NUM_BRU],
    output logic bru_valid_out [is_pkg::NUM_BRU],

    output uop_insn alu_input_out [is_pkg::NUM_ALU],
    output logic alu_valid_out [is_pkg::NUM_ALU],

    output uop_insn fpu_input_out [is_pkg::NUM_FPU],
    output logic fpu_valid_out [is_pkg::NUM_FPU],

    // signal the ROB which instructions have been accepted by the func units
    output logic lsu_insn_executing_out,
    output logic bru_insn_executing_out,
    output logic alu_insn_executing_out,
    output logic fpu_insn_executing_out
);

    logic [is_pkg::NUM_LSU-1:0] lsu_q_full;
    logic [is_pkg::NUM_LSU-1:0] lsu_enq_valid;
    logic [Q_WIDTH-1:0] lsu_enq_data;
    logic [is_pkg::NUM_LSU-1:0] lsu_deq_ready;
    logic [is_pkg::NUM_LSU-1:0] lsu_deq_valid;
    logic [Q_WIDTH-1:0] lsu_deq_data;

    logic [is_pkg::NUM_BRU-1:0] bru_q_full;
    logic [is_pkg::NUM_BRU-1:0] bru_enq_valid;
    logic [Q_WIDTH-1:0] bru_enq_data;
    logic [is_pkg::NUM_BRU-1:0] bru_deq_ready;
    logic [is_pkg::NUM_BRU-1:0] bru_deq_valid;
    logic [Q_WIDTH-1:0] bru_deq_data;

    logic [is_pkg::NUM_ALU-1:0] alu_q_full;
    logic [is_pkg::NUM_ALU-1:0] alu_enq_valid;
    logic [Q_WIDTH-1:0] alu_enq_data;
    logic [is_pkg::NUM_ALU-1:0] alu_deq_ready;
    logic [is_pkg::NUM_ALU-1:0] alu_deq_valid;
    logic [Q_WIDTH-1:0] alu_deq_data;

    logic [is_pkg::NUM_FPU-1:0] fpu_q_full;
    logic [is_pkg::NUM_FPU-1:0] fpu_enq_valid;
    logic [Q_WIDTH-1:0] fpu_enq_data;
    logic [is_pkg::NUM_FPU-1:0] fpu_deq_ready;
    logic [is_pkg::NUM_FPU-1:0] fpu_deq_valid;
    logic [Q_WIDTH-1:0] fpu_deq_data;

    genvar i;
    generate
        for (i = 0; i < is_pkg::NUM_LSU; i++) begin: lsu_queues
            fu_queue #(.Q_DEPTH(Q_DEPTH), .Q_WIDTH(Q_WIDTH)) lsu_q (
                .clk(clk_in),
                .rst(rst_N_in),
                .flush(flush_in),
                .enq_valid(lsu_enq_valid[i]),
                .enq_data(lsu_insn_i),
                .deq_ready(lsu_ready_in[i]),
                .deq_valid(lsu_deq_valid[i]),
                .deq_data(lsu_deq_data[i]),
                .full(lsu_q_full[i])
            );
        end
        for (i = 0; i < is_pkg::NUM_BRU; i++) begin: bru_queues
            fu_queue #(.Q_DEPTH(Q_DEPTH), .Q_WIDTH(Q_WIDTH)) bru_q (
                .clk(clk_in),
                .rst(rst_N_in),
                .flush(flush_in),
                .enq_valid(bru_enq_valid[i]),
                .enq_data(bru_insn_i),
                .deq_ready(bru_ready_in[i]),
                .deq_valid(bru_deq_valid[i]),
                .deq_data(bru_deq_data[i]),
                .full(bru_q_full[i])
            );
        end
        for (i = 0; i < is_pkg::NUM_ALU; i++) begin: alu_queues
            fu_queue #(.Q_DEPTH(Q_DEPTH), .Q_WIDTH(Q_WIDTH)) alu_q (
                .clk(clk_in),
                .rst(rst_N_in),
                .flush(flush_in),
                .enq_valid(alu_enq_valid[i]),
                .enq_data(alu_insn_i),
                .deq_ready(alu_ready_in[i]),
                .deq_valid(alu_deq_valid[i]),
                .deq_data(alu_deq_data[i]),
                .full(alu_q_full[i])
            );
        end
        for (i = 0; i < is_pkg::NUM_FPU; i++) begin: fpu_queues
            fu_queue #(.Q_DEPTH(Q_DEPTH), .Q_WIDTH(Q_WIDTH)) fpu_q (
                .clk(clk_in),
                .rst(rst_N_in),
                .flush(flush_in),
                .enq_valid(fpu_enq_valid[i]),
                .enq_data(fpu_insn_i),
                .deq_ready(fpu_ready_in[i]),
                .deq_valid(fpu_deq_valid[i]),
                .deq_data(fpu_deq_data[i]),
                .full(fpu_q_full[i])
            );
        end
    endgenerate

    always_comb begin
        lsu_enq_valid = '0;
        lsu_enq_data = '0;

        bru_enq_valid = '0;
        bru_enq_data = '0;

        alu_enq_valid = '0;
        alu_enq_data = '0;

        fpu_enq_valid = '0;
        fpu_enq_data = '0;

        lsu_insn_executing_out = 1'b0;
        bru_insn_executing_out = 1'b0;
        alu_insn_executing_out = 1'b0;
        fpu_insn_executing_out = 1'b0;

        if (lsu_insn_in.valid) begin
            for (int i = 0; i < is_pkg::NUM_LSU; i++) begin
                if (!lsu_q_full[i]) begin
                    lsu_enq_valid[i] = 1'b1;
                    lsu_enq_data = lsu_insn_in.uop;
                    lsu_insn_executing_out = 1'b1;
                    break;
                end
            end
        end

        if (bru_insn_in.valid) begin
            for (int i = 0; i < is_pkg::NUM_BRU; i++) begin
                if (!bru_q_full[i]) begin
                    bru_enq_valid[i] = 1'b1;
                    bru_enq_data = bru_insn_in.uop;
                    bru_insn_executing_out = 1'b1;
                    break;
                end
            end
        end

        if (alu_insn_in.valid) begin
            for (int i = 0; i < is_pkg::NUM_ALU; i++) begin
                if (!alu_q_full[i]) begin
                    alu_enq_valid[i] = 1'b1;
                    alu_enq_data = alu_insn_in.uop;
                    alu_insn_executing_out = 1'b1;
                    break;
                end
            end
        end

        if (fpu_insn_in.valid) begin
            for (int i = 0; i < is_pkg::NUM_FPU; i++) begin
                if (!fpu_q_full[i]) begin
                    fpu_enq_valid[i] = 1'b1;
                    fpu_enq_data = fpu_insn_in.uop;
                    fpu_insn_executing_out = 1'b1;
                    break;
                end
            end
        end
    end

    assign lsu_input_out = lsu_deq_data;
    assign lsu_valid_out = lsu_deq_valid && lsu_ready_in;
    assign lsu_deq_ready = lsu_ready_in;

    assign bru_input_out = bru_deq_data;
    assign bru_valid_out = bru_deq_valid && bru_ready_in;
    assign bru_deq_ready = bru_ready_in;

    assign alu_input_out = alu_deq_data;
    assign alu_valid_out = alu_deq_valid && alu_ready_in;
    assign alu_deq_ready = alu_ready_in;

    assign fpu_input_out = fpu_deq_data;
    assign fpu_valid_out = fpu_deq_valid && fpu_ready_in;
    assign fpu_deq_ready = fpu_ready_in;
    
endmodule;