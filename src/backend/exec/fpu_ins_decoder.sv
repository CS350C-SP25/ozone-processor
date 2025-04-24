`include "../../util/uop_pkg.sv"
`include "../packages/rob_pkg.sv"
`include "../packages/is_pkg.sv"
`include "../../fpu/fpmult.sv"
`include "../../fpu/fpadder.sv"

import uop_pkg::*;
import reg_pkg::*;
import rob_pkg::*;
import is_pkg::*;

module fpu_ins_decoder #(
    parameter FP_MULT_LATENCY = 13,
    parameter FP_ADD_LATENCY = 1
) (
    input  logic clk_in,
    input  logic rst_N_in,
    input  logic flush_in,

    // ins from ROB
    input  exec_packet insn_in,

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
    output logic fpmult_valid_out,
    output logic fpadder_valid_out,
    output rob_writeback writeback_out
);
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
    assign fpadder_valid_out = is_fadd | is_fsub;
    assign fpmult_valid_out = is_fmul;

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
            ready_out <= ready && fpu_valid;
        end
    end

    // Register file writeback packet
    always_comb begin
        reg_pkt_out = '0;
        writeback_out = '0;
        if (ready && fpu_valid) begin
            reg_pkt_out.index_in = dest_reg_phys;
            reg_pkt_out.data_in  = fpu_result;
            reg_pkt_out.en       = 1'b1;
            writeback_out = '{
                valid: 1'b1,
                ptr:   insn_in.ptr,
                status: DONE
            };
        end
    end

endmodule
