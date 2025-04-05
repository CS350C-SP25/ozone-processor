import uop_pkg::*;
import reg_pkg::*;
import rob_pkg::*;

// Q_WIDTH must be at least as large as Super scalar * max crack size
module reorder_buffer_queue #(
    parameter Q_DEPTH = rob_pkg::ROB_ENTRIES,
    parameter Q_WIDTH = uop_pkg::INSTR_Q_WIDTH
) (
    input logic clk_in,
    input logic rst_N_in,                       // resets the q completely, empty, 0 size, etc.
    input logic flush_in,                       // same function as reset
    input rob_entry [Q_WIDTH-1:0] q_in,
    input logic [$clog2(Q_WIDTH+1)-1:0] enq_in, // how many to push IMPORTANT, IT IS ENQERS JOB TO DETERMINE HOW MANY IS SAFE TO ENQ
    input logic [$clog2(Q_WIDTH+1)-1:0] deq_in, // how many to pop IMPORTANT, IT IS DEQERS JOB TO DETERMINE HOW MANY IS SAFE TO DEQ (USE SIZE)
    input logic [$clog2(Q_DEPTH)-1:0] idx_in,   // for querying, fully combinational

    output rob_entry [Q_WIDTH-1:0] q_out,       // the top width elements of the queue
    output logic full,                          // 1 if the queue is full
    output logic empty,                         // 1 if the queue is empty
    output logic [$clog2(Q_DEPTH)-1:0] size,    // the #elems in the queue
    output rob_entry entry_out                  // for querying, returns queue[idx_in]
); 
    rob_entry [Q_DEPTH-1:0] q;
    logic [$clog2(Q_DEPTH)-1:0] head;
    logic [$clog2(Q_DEPTH)-1:0] tail;

    rob_entry [Q_WIDTH-1:0] q_next;
    logic [$clog2(Q_WIDTH+1)-1:0] size_incr;
    logic [$clog2(Q_WIDTH+1)-1:0] size_decr; 
    always_ff @( posedge clk_in ) begin : instruction_queue_fsm
        if (rst_N_in && !flush_in) begin
            for (int i = 0; i < Q_WIDTH; i++) begin
                q[tail + i] <= size_incr > i ? q_next[i] : q[tail];
            end
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
        entry_out = q[idx_in + head];
    end
    generate
        genvar i;
        for (i = 0; i < Q_WIDTH; i++) begin: get_top_width
            assign q_out[i] = q[head + i];
        end: get_top_width
    endgenerate
    assign full = (size == Q_DEPTH);
    assign empty = (size == 0);
endmodule: reorder_buffer_queue

module reorder_buffer #(
    parameter Q_DEPTH = rob_pkg::ROB_ENTRIES,
    parameter Q_WIDTH = uop_pkg::INSTR_Q_WIDTH,
    parameter ADDR_BITS = 64,
    parameter WORD_SIZE = 64
) (
    input logic clk_in,
    input logic rst_N_in,
    input rob_entry [Q_WIDTH-1:0] q_in,
    input logic [$clog2(Q_WIDTH+1)-1:0] enq_in,
    output logic valid_pc_out, // if PC needs to be set for exception handling, branch mispredictions, trap, etc..
    output logic [ADDR_BITS-1:0] pc_out,
    output logic[Q_WIDTH-1:0] valid_str_out, // map of which stores are valid
    output logic [Q_WIDTH-1:0][$clog2(reg_pkg::NUM_ARCH_REGS)-1:0] str_addr_reg_out, // arch reg to load STR addr from
    output logic [Q_WIDTH-1:0][$clog2(reg_pkg::NUM_ARCH_REGS)-1:0] str_addr_reg_off_out, // arch reg to load STR addr from
    output logic [Q_WIDTH-1:0][$clog2(reg_pkg::NUM_ARCH_REGS)-1:0] str_val_reg_out // arch reg to load STR val from
);
    // ** REORDER_BUFFER_QUEUE PARAMS **
    // queue input
    logic flush_in;
    logic [$clog2(Q_WIDTH+1)-1:0] deq_in;
    logic [$clog2(Q_DEPTH)-1:0] idx_in;
    // queue output
    rob_entry [Q_WIDTH-1:0] queue_out;
    logic queue_full;
    logic queue_empty;
    logic [$clog2(Q_DEPTH)-1:0] queue_size;
    rob_entry queue_entry_out;

    // ** INTERNAL LOGISTIC WIRES **
    uop_rr cur_uop;

    reorder_buffer_queue #(
        .Q_DEPTH(Q_DEPTH),
        .Q_WIDTH(Q_WIDTH)
    ) reorder_buffer_queue_internal(
        // ** INPUTS ** 
        clk_in,
        rst_N_in,
        flush_in,
        q_in,
        enq_in,
        deq_in,
        idx_in,
        // ** OUTPUTS **
        queue_out,
        queue_full,
        queue_empty,
        queue_size,
        queue_entry_out
    );

    always_ff @(posedge clk_in) begin : reorder_buffer_fsm
        if (rst_N_in) begin // not reset
        end
    end

    always_comb begin
        deq_in = 0;
        str_val_reg_out = '0;
        str_addr_reg_off_out = '0;
        str_addr_reg_out = '0;
        valid_str_out = '0;
        cur_uop = '0;
        if (!queue_empty) begin
            // ** INSTRUCTION WINDOW COMMIT **
            if (queue_size >= uop_pkg::INSTR_Q_WIDTH) begin
                for (int i = 0; i < uop_pkg::INSTR_Q_WIDTH; i++) begin
                    case (queue_out[i])
                        DONE: begin
                            if (queue_out[i].uop.uopcode == UOP_STORE) begin // only str on commit
                                valid_str_out[i] = 1'b1;
                                get_data_rr(queue_out[i].uop.data, cur_uop);
                                str_addr_reg_out[i] = cur_uop.dst.gpr;
                                str_addr_reg_off_out[i] = cur_uop.src2.gpr;
                                str_val_reg_out[i] = cur_uop.src1.gpr;
                            end
                            deq_in += 1;
                            // TODO update RRAT mapping to match architectural state
                        end
                        EXCEPTION: begin
                            // TODO set PC to exception handler
                            break;
                        end
                        INTERRUPT: begin
                            // TODO set PC to interrupt handler
                            break;
                        end
                        TRAP: begin
                            // TODO set PC to exception handler to invoke privileged exec mode
                            break;
                        end
                        default: break;
                    endcase
                end
            end
            // ** PROVIDE ISSUE INSN OPTIONS FOR EXEC **
            for (int i = 0; i < queue_size; i++) begin
                idx_in = i;
                if (
                    queue_entry_out.uop.uopcode == UOP_ADD || 
                    queue_entry_out.uop.uopcode == UOP_SUB
                    ) begin
                    end else if (
                        queue_entry_out.uop.uopcode == UOP_FADD || 
                        queue_entry_out.uop.uopcode == UOP_FSUB || 
                        queue_entry_out.uop.uopcode == UOP_FMUL || 
                        queue_entry_out.uop.uopcode == UOP_FNEG
                    )
            end
        end
    end
endmodule: reorder_buffer