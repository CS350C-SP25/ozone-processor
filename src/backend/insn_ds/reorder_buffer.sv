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
    input logic rst_N_in,
    input logic flush_in,

    input rob_entry [Q_WIDTH-1:0] q_in,
    input logic [$clog2(Q_WIDTH+1)-1:0] deq_in,
    input rob_writeback [3:0] writeback_in,
    input rob_writeback [3:0] issue_mark_pending,

    output rob_entry [Q_DEPTH-1:0] q_out,
    output logic full,
    output logic empty,
    output logic [$clog2(Q_DEPTH)-1:0] size
);

    typedef rob_entry rob_q [Q_DEPTH-1:0];
    rob_q q;
    rob_q q_next;

    logic [$clog2(Q_DEPTH)-1:0] head, tail;
    logic [$clog2(Q_DEPTH)-1:0] head_next, tail_next;

    logic [$clog2(Q_WIDTH+1)-1:0] size_incr, size_decr;
    logic [$clog2(Q_DEPTH)-1:0] size_next;

    always_comb begin : compute_next_state
        q_next = q;
        head_next = head;
        tail_next = tail;
        size_incr = 0;
        size_decr = flush_in ? tail - head : deq_in;

        // Enqueue new instructions
        for (int i = 0; i < Q_WIDTH; i++) begin
            if (q_in[i].uop.valid && tail_next < Q_DEPTH) begin
                q_next[tail_next] = q_in[i];
                tail_next++;
                size_incr++;
            end
        end

        // Handle writebacks and issue marks
        for (int i = 0; i < 4; i++) begin
            if (writeback_in[i].valid) begin
                q_next[writeback_in[i].ptr].status = writeback_in[i].status;
            end else if (issue_mark_pending[i].valid) begin
                q_next[issue_mark_pending[i].ptr].status = ISSUED;
            end
        end

        if (flush_in) begin
            head_next = '0;
            tail_next = '0;
            size_next = '0;
        end else begin
            head_next = head + size_decr;
            size_next = tail_next - head_next;
        end
    end

    always_ff @(posedge clk_in) begin
        if (!rst_N_in || flush_in) begin
            head <= '0;
            tail <= '0;
            size <= '0;
            //for (int i = 0; i < Q_DEPTH; i++) begin
                q <= 0;
            //end
        end else begin
            head <= head_next;
            tail <= tail_next;
            size <= size_next;
            //for (int i = 0; i < Q_DEPTH; i++) begin
                //q[i] <= q_next[i];
            //end
            q <= q_next;
        end
    end

    generate
        genvar i;
        for (i = 0; i < Q_DEPTH; i++) begin : gen_q_out
            assign q_out[i] = q[i];
        end
    endgenerate
    assign full  = (size == Q_DEPTH);
    assign empty = (size == 0);

endmodule : reorder_buffer_queue

module reorder_buffer #(
    parameter Q_DEPTH = rob_pkg::ROB_ENTRIES,
    parameter Q_WIDTH = uop_pkg::INSTR_Q_WIDTH,
    parameter ADDR_BITS = 64,
    parameter WORD_SIZE = 64
) (
    input logic clk_in,
    input logic rst_N_in,
    input rob_entry [Q_WIDTH-1:0] q_in,

    // ** INPUTS FROM BRANCH UNIT **
    input logic flush_in, // fed from either RESET or branch misprediction

    // ** INPUTS FROM INSTR_SCHEDULER **
    input logic alu_ready_in,
    input logic fpu_ready_in,
    input logic lsu_ready_in,
    input logic bru_ready_in,
    input rob_writeback [3:0] writeback_in, // tell rob which entries to update
    input rob_bru bru_writeback_in, // tell rob bru update
    input logic bru_wb_valid_in,
    input logic [$clog2(Q_DEPTH)-1:0] bru_wb_ptr_in,

    // ** INPUTS FROM REG_FILE **
    input logic [reg_pkg::NUM_PHYS_REGS-1:0] scoreboard_in, // scoreboard from reg file to check if the register is valid or not    

    // ** EXEC OUTPUT LOGIC **
    // these outputs will be sent to the execute phase where insn scheduler will decide which ones we can execute
    output rob_issue lsu_insn_out,
    output rob_issue bru_insn_out, 
    output rob_issue alu_insn_out, 
    output rob_issue fpu_insn_out,

    output rob_entry [uop_pkg::INSTR_Q_WIDTH-1:0] rrat_update_out, // update the rrat mapping for the physical reg to arch reg mapping
    output logic [uop_pkg::INSTR_Q_WIDTH-1:0] rrat_update_valid_out, // 1 if the rrat update is valid
    output logic bru_wb_valid_out,
    output rob_bru bru_writeback_out,

    output logic rob_ready_out // ready to accept new instructions
);
    // ** REORDER_BUFFER_QUEUE PARAMS **
    // queue input
    logic [$clog2(Q_WIDTH+1)-1:0] deq_in;
    // queue output
    rob_entry [Q_DEPTH-1:0] queue_out;
    logic queue_full;
    logic queue_empty;
    logic [$clog2(Q_DEPTH)-1:0] queue_size;
    rob_writeback [3:0] issue_mark_pending; // mark pending instructions as issued
    logic [1:0] next_issue_ptr;

    // ** INTERNAL LOGISTIC WIRES **
    uop_rr cur_uop;
    rob_entry cur_entry;
    logic cur_lsu_check; // are dependencies satisfied
    logic cur_bru_check;
    logic cur_alu_check;
    logic cur_fpu_check;
    logic next_check;
    logic [$clog2(uop_pkg::INSTR_Q_WIDTH)-1:0] next_rrat_ptr; // idx for rrat update

    // registers
    rob_issue lsu_insn_out_t;
    rob_issue bru_insn_out_t;
    rob_issue alu_insn_out_t;
    rob_issue fpu_insn_out_t;

    rob_bru [Q_DEPTH-1:0] bru_status;

    assign rob_ready_out = !queue_full;

    reorder_buffer_queue #(
        .Q_DEPTH(Q_DEPTH),
        .Q_WIDTH(Q_WIDTH)
    ) reorder_buffer_queue_internal(
        // ** INPUTS ** 
        clk_in,
        rst_N_in,
        flush_in,
        q_in,
        deq_in,
        writeback_in,
        issue_mark_pending,
        // ** OUTPUTS **
        queue_out,
        queue_full,
        queue_empty,
        queue_size
    );

    function automatic void insn_check(
        input logic cur_check,
        input rob_entry cur_entry,
        input logic dep_check, // are dependencies satisfied
        input logic [$clog2(Q_DEPTH)-1:0] queue_size,
        input rob_entry [Q_DEPTH-1:0] queue_out,
        input logic [$clog2(Q_DEPTH)-1:0] i,
        output logic next_check,
        output rob_issue insn_out_t
    );
        next_check = 1'b0;
        insn_out_t = '0;
        next_check = '0;
        if (cur_check == 1'b0) begin
            $display("[ROB] Considering scheduling current instruction %0d {UOPCODE: %0b}", i, cur_entry.uop.uopcode);
            next_check = 1'b1;
            if (!dep_check || cur_entry.status != READY) begin
                next_check = 1'b0;
                $display("[ROB] Instruction %0d was not scheduled because dependencies were not satisfied or its already been issued", i);
            end
            if (next_check == 1'b1) begin
                $display("[ROB] Instruction %0d was scheduled", i);
                insn_out_t.valid = 1'b1;
                insn_out_t.uop = cur_entry.uop;
                insn_out_t.ptr = i;
                insn_out_t.dest_reg_phys = cur_entry.dest_reg_phys;
                insn_out_t.r1_reg_phys = cur_entry.r1_reg_phys;
                insn_out_t.r2_reg_phys = cur_entry.r2_reg_phys;
                insn_out_t.nzcv_reg_phys = cur_entry.nzcv_reg_phys;
            end
        end
    endfunction

    always_ff @(posedge clk_in) begin : reorder_buffer_fsm
        if (rst_N_in) begin // not reset
            bru_insn_out <= bru_insn_out_t;
            alu_insn_out <= alu_insn_out_t;
            fpu_insn_out <= fpu_insn_out_t;
            lsu_insn_out <= lsu_insn_out_t;
            if (bru_wb_valid_in) begin
                bru_status[bru_wb_ptr_in] <= bru_writeback_in;
            end  
        end
    end

    always_comb begin
        deq_in = 0;

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
        issue_mark_pending = '0;
        next_issue_ptr = '0;   
        if (!queue_empty) begin
            
            // ** INSTRUCTION WINDOW COMMIT **
            if (queue_size >= uop_pkg::INSTR_Q_WIDTH) begin
                for (int i = 0; i < uop_pkg::INSTR_Q_WIDTH; i++) begin
                    if (queue_out[i].status == DONE) begin
                        if (queue_out[i].uop.uopcode == UOP_STORE) begin // only str on commit
                            insn_check(
                                cur_lsu_check,
                                cur_entry,
                                scoreboard_in[cur_entry.r1_reg_phys] && scoreboard_in[cur_entry.r2_reg_phys],
                                queue_size,
                                queue_out,
                                i[6:0],
                                next_check,
                                lsu_insn_out_t
                            );
                            cur_lsu_check = next_check; // commit store will take priority over any load in the buffer
                        end else if (queue_out[i].uop.uopcode == UOP_BCOND || queue_out[i].uop.uopcode == UOP_BL) begin
                            bru_writeback_out = bru_status[i];
                            bru_wb_valid_out = 1'b1;
                        end
                        deq_in += 1;
                        // update RRAT mapping to match architectural state
                        rrat_update_out[next_rrat_ptr] = queue_out[i];
                        rrat_update_valid_out[next_rrat_ptr] = 1'b1;
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
                            // LDUR is M format which specifies 1 register and 1 imm, but all imms will be written to regs. 
                            insn_check(
                                cur_lsu_check,
                                cur_entry,
                                scoreboard_in[cur_entry.r1_reg_phys] && scoreboard_in[cur_entry.r2_reg_phys],
                                queue_size,
                                queue_out,
                                i,
                                next_check,
                                lsu_insn_out_t
                            );
                            cur_lsu_check = next_check;
                            issue_mark_pending[next_issue_ptr] = '{valid: 1'b1, ptr: i, status: ISSUED};
                            next_issue_ptr = next_issue_ptr + 1;
                        end
                    end
                    UOP_MOVZ, UOP_MOVK, UOP_ADRP_MOV: begin
                        if (alu_ready_in) begin
                            // Data processing immediates (only 1 immediate value which will be written to r2)
                            $display ("Reg Status %0d", scoreboard_in[cur_entry.r2_reg_phys]);
                            insn_check(
                                cur_alu_check,
                                cur_entry,
                                scoreboard_in[cur_entry.r2_reg_phys],
                                queue_size,
                                queue_out,
                                i,
                                next_check,
                                alu_insn_out_t
                            );
                            cur_alu_check = next_check;
                            issue_mark_pending[next_issue_ptr] = '{valid: 1'b1, ptr: i, status: ISSUED};
                            next_issue_ptr = next_issue_ptr + 1;
                        end
                    end
                    UOP_ADD, UOP_SUB, UOP_AND, UOP_ORR, 
                    UOP_EOR, UOP_MVN, UOP_UBFM, 
                    UOP_ASR: begin
                        if (alu_ready_in) begin
                            insn_check(
                                cur_alu_check,
                                cur_entry,
                                scoreboard_in[cur_entry.r1_reg_phys] && scoreboard_in[cur_entry.r2_reg_phys],
                                queue_size,
                                queue_out,
                                i,
                                next_check,
                                alu_insn_out_t
                            );
                            cur_alu_check = next_check;
                            issue_mark_pending[next_issue_ptr] = '{valid: 1'b1, ptr: i, status: ISSUED};
                            next_issue_ptr = next_issue_ptr + 1;
                        end
                    end
                    UOP_FMOV, 
                    UOP_FNEG, UOP_FADD, UOP_FMUL, UOP_FSUB: begin
                        if (fpu_ready_in) begin
                            insn_check(
                                cur_fpu_check,
                                cur_entry,
                                scoreboard_in[cur_entry.r1_reg_phys] && scoreboard_in[cur_entry.r2_reg_phys],
                                queue_size,
                                queue_out,
                                i,
                                next_check,
                                fpu_insn_out_t
                            );
                            cur_fpu_check = next_check;
                            issue_mark_pending[next_issue_ptr] = '{valid: 1'b1, ptr: i, status: ISSUED};
                            next_issue_ptr = next_issue_ptr + 1;
                        end
                    end
                    UOP_BCOND: begin
                        if (bru_ready_in) begin
                            // Branching instructions only have 1 immediate which will be written to a register
                            insn_check(
                                cur_bru_check,
                                cur_entry,
                                scoreboard_in[cur_entry.r1_reg_phys],
                                queue_size,
                                queue_out,
                                i,
                                next_check,
                                bru_insn_out_t
                            );
                            cur_bru_check = next_check;
                            issue_mark_pending[next_issue_ptr] = '{valid: 1'b1, ptr: i, status: ISSUED};
                            next_issue_ptr = next_issue_ptr + 1;
                        end
                    end
                endcase
            end
        end
    end
endmodule: reorder_buffer
