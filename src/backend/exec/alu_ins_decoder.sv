`include "../../util/uop_pkg.sv"
`include "../reg_pkg.sv"
`include "../rob_pkg.sv"
`include "../is_pkg.sv"
`include "../../fpu/fpmult.sv"
`include "../../fpu/fpadder.sv"

import uop_pkg::*;
import reg_pkg::*;
import is_pkg::*;
import rob_pkg::*;

/*
When ins_sched receives ins from rob, it immediately schedules. This is the simplest and cheapest way to do it. 
ins_sched tells rob whether its ready to receive ins or not
We have schedulers for each functional unit to make life easier. 
*/
module alu_ins_decoder (
    input logic clk_in,

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