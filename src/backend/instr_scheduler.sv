`include "../util/uop_pkg.sv"
`include "./reg_pkg.sv"
`include "./rob_pkg.sv"
`include "./is_pkg.sv"
`include "../fpu/fpmult.sv"
`include "../fpu/fpadder.sv"

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
    input rob_issue [Q_WIDTH-1:0] enq_data,

    // dequeue
    input logic deq_ready,  // getting the request to dequeue
    output logic deq_valid, // deq_data holds valid dequeued data
    output rob_issue [Q_WIDTH-1:0] deq_data,

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

/*
When ins_sched receives ins from rob, it immediately schedules. This is the simplest and cheapest way to do it. 
ins_sched tells rob whether its ready to receive ins or not
We have schedulers for each functional unit to make life easier. 
*/
module alu_scheduler #(
    parameter Q_DEPTH = is_pkg::FQ_ENTRIES,
    parameter Q_WIDTH = is_pkg::FQ_EL_SIZE
) (
    input logic clk_in,
    input logic rst_N_in,
    input logic flush_in,

    // ins from ROB
    input rob_issue insn_in,
    // tell ROB if ALU is "ready"
    output logic ready_out,
    // signal regfile how to write data
    output RegFileWritePort reg_pkt_out
);
    uop_ri reg_imm;
    always_ff @(posedge clk_in) begin
        if (insn_in.valid) begin
            ready_out <= '0;
        end else begin
            ready_out <= '1;
        end
    end
    always_comb begin
        reg_pkt_out = '0;
        reg_imm = '0;
        if (insn_in.valid) begin
            reg_pkt_out.index_in = insn_in.dest_reg_phys;
            reg_pkt_out.en = 1'b1;
            get_data_ri(insn_in.uop.data, reg_imm);
            case(insn_in.uop.uopcode)
                UOP_ADD: reg_pkt_out.data_in = insn_in.r1_val+insn_in.r2_val;
                UOP_SUB: reg_pkt_out.data_in = insn_in.r1_val-insn_in.r2_val;
                UOP_AND: reg_pkt_out.data_in = insn_in.r1_val&insn_in.r2_val;
                UOP_ORR: reg_pkt_out.data_in = insn_in.r1_val|insn_in.r2_val;
                UOP_EOR: reg_pkt_out.data_in = insn_in.r1_val^insn_in.r2_val;
                UOP_MVN: reg_pkt_out.data_in = ~insn_in.r1_val;
                UOP_UBFM: reg_pkt_out.data_in = (insn_in.r0_val >> reg_imm.imm[5:0]) & 
                    ((1 << (reg_imm.imm[11:6] - reg_imm.imm[5:0] + 1)) - 1);
                UOP_ASR: reg_pkt_out.data_in = $signed(insn_in.r0_val) >>> insn_in.r1_val;
                UOP_MOVZ: reg_pkt_out.data_in = insn_in.r1_val << reg_imm.hw * 16;
                UOP_MOVK: reg_pkt_out.data_in = (insn_in.r0_val & ~(16'hFFFF << (reg_imm.hw * 16))) | (insn_in.r1_val << (reg_imm.hw * 16));
            endcase
        end
    end
endmodule

module fpu_scheduler #(
    parameter Q_DEPTH = is_pkg::FQ_ENTRIES,
    parameter Q_WIDTH = is_pkg::FQ_EL_SIZE,
    parameter FP_MULT_LATENCY = 13,
    parameter FP_ADD_LATENCY = 1
) (
    input  logic clk_in,
    input  logic rst_N_in,
    input  logic flush_in,

    // ins from ROB
    input  rob_issue insn_in,

    // input from FPU
    input  logic [reg_pkg::WORD_SIZE-1:0] fpu_result,
    input  logic fpu_valid,

    // tell ROB if ALU is "ready"
    output logic ready_out,

    // signal regfile how to write data
    output RegFileWritePort reg_pkt_out,

    // outputs to FPU
    output logic [reg_pkg::WORD_SIZE-1:0] fpu_a_out,
    output logic [reg_pkg::WORD_SIZE-1:0] fpu_b_out,
    output logic fpu_valid_out
);

    // Internal tracking
    logic [31:0] cycle_count;
    logic [31:0] cycle_expiration;
    logic ready;

    logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] dest_reg_phys;

    // UOP decode
    logic is_fadd, is_fsub, is_fmul;
    assign is_fadd = insn_in.valid && (insn_in.uop.uopcode == UOP_FADD);
    assign is_fsub = insn_in.valid && (insn_in.uop.uopcode == UOP_FSUB);
    assign is_fmul = insn_in.valid && (insn_in.uop.uopcode == UOP_FMUL);

    // FPU operand selection
    assign fpu_a_out = (is_fadd | is_fsub | is_fmul) ? insn_in.r1_val : '0;
    assign fpu_b_out = is_fadd ? insn_in.r2_val :
                       is_fsub ? ~insn_in.r2_val + 1 :
                       is_fmul ? insn_in.r2_val : '0;
    assign fpu_valid_out = is_fadd | is_fsub | is_fmul;

    // Main control logic
    always_ff @(posedge clk_in or negedge rst_N_in) begin
        if (!rst_N_in || flush_in) begin
            cycle_count <= '0;
            cycle_expiration <= '0;
            dest_reg_phys <= '0;
            ready <= 1;
            ready_out <= 0;
        end else begin
            cycle_count <= cycle_count + 1;

            // Dispatch new FP instruction
            if (insn_in.valid && (is_fadd || is_fsub || is_fmul)) begin
                dest_reg_phys <= insn_in.dest_reg_phys;
                cycle_expiration <= cycle_count + (is_fmul ? FP_MULT_LATENCY : FP_ADD_LATENCY);
                ready <= 0;
            end else begin
                ready <= (cycle_count == cycle_expiration);
            end

            // Signal ready_out only when result is valid
            ready_out <= ready && fpu_valid;
        end
    end

    // Register file writeback packet
    always_comb begin
        reg_pkt_out = '0;
        if (ready && fpu_valid) begin
            reg_pkt_out.index_in = dest_reg_phys;
            reg_pkt_out.data_in  = fpu_result;
            reg_pkt_out.en       = 1'b1;
        end
    end

endmodule

