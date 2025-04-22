`include "../util/uop_pkg.sv"
import uop_pkg::*;
// Q_WIDTH must be at least as large as Super scalar * max crack size
module instruction_queue #(
    parameter Q_DEPTH = uop_pkg::INSTR_Q_DEPTH,
    parameter Q_WIDTH = uop_pkg::INSTR_Q_WIDTH
) 
(
    input logic clk_in,
    input logic rst_N_in,                       // resets the q completely, empty, 0 size, etc.
    input logic flush_in,                       // same function as reset
    input uop_insn [Q_WIDTH-1:0] q_in,
    input logic [$clog2(Q_WIDTH+1)-1:0] enq_in, // how many to push IMPORTANT, IT IS ENQERS JOB TO DETERMINE HOW MANY IS SAFE TO ENQ
    input logic [$clog2(Q_WIDTH+1)-1:0] deq_in, // how many to pop IMPORTANT, IT IS DEQERS JOB TO DETERMINE HOW MANY IS SAFE TO DEQ (USE SIZE)

    output uop_insn [Q_WIDTH-1:0] q_out,       // the top width elements of the queue
    output logic full,                         // 1 if the queue is full
    output logic empty,                         // 1 if the queue is empty
    output logic [$clog2(Q_DEPTH)-1:0] size,    // the #elems in the queue
); 
    uop_insn [Q_DEPTH-1:0] q;
    logic [$clog2(Q_DEPTH)-1:0] head;
    logic [$clog2(Q_DEPTH)-1:0] tail;

    uop_insn [Q_WIDTH-1:0] q_next;
    logic [$clog2(Q_WIDTH+1)-1:0] size_incr;
    logic [$clog2(Q_WIDTH+1)-1:0] size_decr; 
    always_ff @( posedge clk_in ) begin : instruction_queue_fsm
        if (rst_N_in && !flush_in) begin
            generate
                for (genvar i = 0; i < Q_WIDTH; i++) begin
                    q[tail + i] <= size_incr > i ? q_next[i] : q[tail];
                end
            endgenerate
            head <= head + size_decr;
            tail <= tail + size_incr;
            size <= tail - head + size_incr - size_decr;
        end else begin
            head <= '0;
            tail <= '0;
            size <= '0;
        end
    end

    always_comb begin : instruction_queue_next_state
        q_next = q_in;
        size_incr = flush_in ? 0 : enq_in;
        size_decr = flush_in ? tail - head : deq_in;
    end
    generate
        for (genvar i = 0; i < Q_WIDTH; i++) begin
            assign q_out[i] <= q[head + i];
        end
    endgenerate
    assign full = (size == Q_DEPTH);
    assign empty = (size == 0);
endmodule