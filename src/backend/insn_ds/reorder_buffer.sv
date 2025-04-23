`include "../../util/uop_pkg.sv"
`include "../packages/reg_pkg.sv"
`include "../packages/rob_pkg.sv"
`include "../packages/is_pkg.sv"

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

    output rob_entry [Q_DEPTH-1:0] q_out,       // the top width elements of the queue
    output logic full,                          // 1 if the queue is full
    output logic empty,                         // 1 if the queue is empty
    output logic [$clog2(Q_DEPTH)-1:0] size    // the #elems in the queue
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
    end
    assign q_out = q;
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

    // ** INPUTS FROM BRANCH UNIT **
    input logic flush_in, // fed from either RESET or branch misprediction
    input logic [ADDR_BITS-1:0] target_pc, // if branch misprediction, this is the target pc

    // ** INPUTS FROM INSTR_SCHEDULER **
    input logic alu_ready_in,
    input logic fpu_ready_in,
    input logic lsu_ready_in,
    input logic bru_ready_in,

    // ** PC OUTPUT LOGIC **
    output logic valid_pc_out, // if PC needs to be set for exception handling, branch mispredictions, trap, etc..
    output logic [ADDR_BITS-1:0] pc_out,

    // ** STR OUTPUT LOGIC **
    output logic[Q_WIDTH-1:0] valid_str_out, // map of which stores are valid
    output logic [Q_WIDTH-1:0][$clog2(reg_pkg::NUM_ARCH_REGS)-1:0] str_addr_reg_out, // arch reg to load STR addr from
    output logic [Q_WIDTH-1:0][$clog2(reg_pkg::NUM_ARCH_REGS)-1:0] str_addr_reg_off_out, // arch reg to load STR addr from
    output logic [Q_WIDTH-1:0][$clog2(reg_pkg::NUM_ARCH_REGS)-1:0] str_val_reg_out, // arch reg to load STR val from

    // ** EXEC OUTPUT LOGIC **
    // these outputs will be sent to the execute phase where insn scheduler will decide which ones we can execute
    output rob_issue lsu_insn_out,
    output rob_issue bru_insn_out, 
    output rob_issue alu_insn_out, 
    output rob_issue fpu_insn_out,

    output rob_entry [1:0] rrat_update_out, // update the rrat mapping for the physical reg to arch reg mapping
    output logic [1:0] rrat_update_valid_out, // 1 if the rrat update is valid
);
    // ** REORDER_BUFFER_QUEUE PARAMS **
    // queue input
    logic [$clog2(Q_WIDTH+1)-1:0] deq_in;
    // queue output
    rob_entry [Q_DEPTH-1:0] queue_out;
    logic queue_full;
    logic queue_empty;
    logic [$clog2(Q_DEPTH)-1:0] queue_size;

    // ** INTERNAL LOGISTIC WIRES **
    uop_rr cur_uop;
    rob_entry cur_entry;
    logic cur_lsu_check; // are dependencies satisfied
    logic cur_bru_check;
    logic cur_alu_check;
    logic cur_fpu_check;
    logic next_check;
    logic next_rrat_ptr; // idx for rrat update

    // registers
    rob_issue lsu_insn_out_t;
    rob_issue bru_insn_out_t;
    rob_issue alu_insn_out_t;
    rob_issue fpu_insn_out_t;

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
        // ** OUTPUTS **
        queue_out,
        queue_full,
        queue_empty,
        queue_size
    );

    function automatic void insn_check(
        input logic cur_check,
        input rob_entry cur_entry,
        input logic [$clog2(Q_DEPTH)-1:0] queue_size,
        input rob_entry [Q_DEPTH-1:0] queue_out,
        input logic [$clog2(Q_DEPTH)-1:0] i,
        output logic next_check,
        output rob_issue insn_out_t
    );
        next_check = 1'b0;
        if (cur_check == 1'b0) begin
            next_check = 1'b1;
            for (int k = 0; k < 2; k++) begin
                if (cur_entry.dependent_entries[k] < queue_size) begin
                    rob_entry cur_dep_entry;
                    cur_dep_entry = queue_out[cur_entry.dependent_entries[k]];
                    if (cur_dep_entry.status == ISSUED || cur_dep_entry.status == READY) begin
                        // this means the dep insn is completed, or ran into an exception that "has been handled"
                        next_check = 1'b0;
                    end
                end
            end
            if (next_check == 1'b1) begin
                insn_out_t.uop = cur_entry.uop;
                insn_out_t.ptr = i;
            end
        end
    endfunction

    always_ff @(posedge clk_in) begin : reorder_buffer_fsm
        if (rst_N_in) begin // not reset
            bru_insn_out <= bru_insn_out_t;
            alu_insn_out <= alu_insn_out_t;
            fpu_insn_out <= fpu_insn_out_t;
            lsu_insn_out <= lsu_insn_out_t;
        end
    end

    always_comb begin
        deq_in = 0;

        str_val_reg_out = '0;
        str_addr_reg_off_out = '0;
        str_addr_reg_out = '0;
        valid_str_out = '0;

        cur_uop = '0;
        cur_entry = '0;
        next_check = '0;

        cur_lsu_check = '0;
        cur_bru_check = '0;
        cur_alu_check = '0;
        cur_fpu_check = '0;
        next_rrat_ptr = '0;

        lsu_insn_out_t = '0;
        bru_insn_out_t = '0;
        alu_insn_out_t = '0;
        fpu_insn_out_t = '0;
        valid_pc_out = flush_in;
        pc_out = target_pc;        
        if (!queue_empty) begin
            // ** INSTRUCTION WINDOW COMMIT **
            if (queue_size >= uop_pkg::INSTR_Q_WIDTH) begin
                for (int i = 0; i < uop_pkg::INSTR_Q_WIDTH; i++) begin
                    if (queue_out[i].status == DONE) begin
                        if (queue_out[i].uop.uopcode == UOP_STORE) begin // only str on commit
                            valid_str_out[i] = 1'b1;
                            get_data_rr(queue_out[i].uop.data, cur_uop);
                            str_addr_reg_out[i] = cur_uop.dst.gpr;
                            str_addr_reg_off_out[i] = cur_uop.src2.gpr;
                            str_val_reg_out[i] = cur_uop.src1.gpr;
                        end
                        deq_in += 1;
                        // update RRAT mapping to match architectural state
                        rrat_update_out[next_rrat_ptr] = queue_out[i];
                    end else if (
                        queue_out[i].status == EXCEPTION || 
                        queue_out[i].status == INTERRUPT || 
                        queue_out[i].status == TRAP) begin
                        // normally would be separated but for the sake of demonstration just turn on a LED or smth
                    end
                    if (queue_out[i].status == READY || next_rrat_ptr == 1) begin
                        break;
                    end
                    next_rrat_ptr = 1; // shortcut for addition since its only 2-issue
                end
            end
            // ** PROVIDE ISSUE INSN OPTIONS FOR EXEC **
            for (int i = 0; i < queue_size && i < Q_DEPTH; i++) begin
                cur_entry = queue_out[i];
                case (cur_entry.uop.uopcode)
                    UOP_STORE: begin
                        if (cur_lsu_check == 1'b0) begin
                            cur_lsu_check = i == 0;
                            if (cur_lsu_check == 1'b1) begin
                                lsu_insn_out_t.uop = cur_entry.uop;
                                lsu_insn_out_t.ptr = i;
                            end
                        end
                    end 
                    UOP_LOAD: begin
                        if (lsu_ready_in) begin
                            insn_check(
                                cur_lsu_check,
                                cur_entry,
                                queue_size,
                                queue_out,
                                i,
                                next_check,
                                lsu_insn_out_t
                            );
                            cur_lsu_check = next_check;
                        end
                    end
                    UOP_ADD, UOP_SUB, UOP_AND, UOP_ORR, 
                    UOP_EOR, UOP_MVN, UOP_UBFM, 
                    UOP_ASR, UOP_MOVZ, UOP_MOVK: begin
                        if (alu_ready_in) begin
                            insn_check(
                                cur_alu_check,
                                cur_entry,
                                queue_size,
                                queue_out,
                                i,
                                next_check,
                                alu_insn_out_t
                            );
                            cur_alu_check = next_check;
                        end
                    end
                    UOP_FMOV, 
                    UOP_FNEG, UOP_FADD, UOP_FMUL, UOP_FSUB: begin
                        if (fpu_ready_in) begin
                            insn_check(
                                cur_fpu_check,
                                cur_entry,
                                queue_size,
                                queue_out,
                                i,
                                next_check,
                                fpu_insn_out_t
                            );
                            cur_fpu_check = next_check;
                        end
                    end
                    UOP_BCOND: begin
                        if (bru_ready_in) begin
                            insn_check(
                                cur_bru_check,
                                cur_entry,
                                queue_size,
                                queue_out,
                                i,
                                next_check,
                                bru_insn_out_t
                            );
                            cur_bru_check = next_check;
                        end
                    end
                endcase
            end
        end
    end
endmodule: reorder_buffer
