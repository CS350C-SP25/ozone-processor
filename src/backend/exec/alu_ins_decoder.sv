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
    input  logic clk_in,
    input  rob_issue insn_in,
    output logic ready_out,
    output RegFileWritePort reg_pkt_out,
    output NZCVWritePort nzcv_out
);
    uop_ri reg_imm;
    logic [63:0] result_add, result_sub, result_and, result_or, result_eor, result_mvn;
    logic [63:0] result_ubfm, result_asr, result_movz, result_movk;
    logic [63:0] result_final;
    logic [3:0] flags;
    logic [63:0] r0, r1, r2;

    assign r0 = insn_in.r0_val;
    assign r1 = insn_in.r1_val;
    assign r2 = insn_in.r2_val;

    always_ff @(posedge clk_in) begin
        ready_out <= ~insn_in.valid;
    end

    always_comb begin
        reg_pkt_out = '0;
        reg_imm     = '0;
        flags       = 4'd0;
        nzcv_out    = '{valid: 1'b0, nzcv: 4'd0};

        result_add  = r1 + r2;
        result_sub  = r1 - r2;
        result_and  = r1 & r2;
        result_or   = r1 | r2;
        result_eor  = r1 ^ r2;
        result_mvn  = ~r1;
        result_ubfm = (r0 >> insn_in.uop.data[5:0]) & ((1 << (insn_in.uop.data[11:6] - insn_in.uop.data[5:0] + 1)) - 1);
        result_asr  = $signed(r0) >>> r1;
        result_movz = r1 << (reg_imm.hw * 16);
        result_movk = (r0 & ~(64'hFFFF << (reg_imm.hw * 16))) | (r1 << (reg_imm.hw * 16));

        // Default result
        result_final = '0;
        case (insn_in.uop.uopcode)
            UOP_ADD:  result_final = result_add;
            UOP_SUB:  result_final = result_sub;
            UOP_AND:  result_final = result_and;
            UOP_ORR:  result_final = result_or;
            UOP_EOR:  result_final = result_eor;
            UOP_MVN:  result_final = result_mvn;
            UOP_UBFM: result_final = result_ubfm;
            UOP_ASR:  result_final = result_asr;
            UOP_MOVZ: result_final = result_movz;
            UOP_MOVK: result_final = result_movk;
            default:  result_final = '0;
        endcase

        if (insn_in.valid) begin
            reg_pkt_out.index_in = insn_in.dest_reg_phys;
            reg_pkt_out.data_in  = result_final;
            reg_pkt_out.en       = 1'b1;

            get_data_ri(insn_in.uop.data, reg_imm);

            if (reg_imm.set_nzcv) begin
                flags[3] = result_final[63];               // N
                flags[2] = (result_final == 64'd0);        // Z
                flags[1] = 1'b0;
                flags[0] = 1'b0;
                case (insn_in.uop.uopcode)
                    UOP_ADD: begin
                        flags[1] = (result_final < r1); // C
                        flags[0] = (~(r1[63] ^ r2[63]) & (r1[63] ^ result_final[63])); // V
                    end
                    UOP_SUB: begin
                        flags[1] = (r1 >= r2);          // C
                        flags[0] = ((r1[63] ^ r2[63]) & (r1[63] ^ result_final[63])); // V
                    end
                endcase
                nzcv_out = '{valid: 1'b1, nzcv: flags};
            end
        end
    end
endmodule
