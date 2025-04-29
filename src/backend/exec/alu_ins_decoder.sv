`include "../../util/uop_pkg.sv"
`include "../packages/reg_pkg.sv"
`include "../packages/rob_pkg.sv"
`include "../packages/is_pkg.sv"
`include "../../fpu/fpmult.sv"
`include "../../fpu/fpadder.sv"

import uop_pkg::*;
import reg_pkg::*;
import rob_pkg::*;
import is_pkg::*;

/*
When ins_sched receives ins from rob, it immediately schedules. This is the simplest and cheapest way to do it. 
ins_sched tells rob whether its ready to receive ins or not
We have schedulers for each functional unit to make life easier. 
*/
module alu_ins_decoder (
    input  logic clk_in,
    input  exec_packet insn_in,
    input logic [3:0] nzcv_in,
    output logic ready_out,
    output RegFileWritePort reg_pkt_out,
    output NZCVWritePort nzcv_out,
    output rob_writeback writeback_out
);
    uop_ri reg_imm;
    uop_rr reg_rr;
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
        nzcv_out    = '{valid: 1'b0, nzcv: nzcv_in, index_in: insn_in.nzcv_reg_phys};

        result_add  = r1 + r2;
        result_sub  = r1 - r2;
        result_and  = r1 & r2;
        result_or   = r1 | r2;
        result_eor  = r1 ^ r2;
        result_mvn  = ~r1;
        result_ubfm = (r0 >> insn_in.uop.data[5:0]) & ((1 << (insn_in.uop.data[11:6] - insn_in.uop.data[5:0] + 1)) - 1);
        result_asr  = $signed(r0) >>> r1;
        result_movz = r2 << (reg_imm.hw * 16);
        result_movk = (r0 & ~(64'hFFFF << (reg_imm.hw * 16))) | (r2 << (reg_imm.hw * 16));
        writeback_out = '0;

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
            $display("[ALU] Writing to register %0d: %0h", insn_in.dest_reg_phys, result_final);

            get_data_ri(insn_in.uop.data, reg_imm);
            get_data_rr(insn_in.uop.data, reg_rr);

            if ((insn_in.uop.valb_sel && reg_rr.set_nzcv) || (~insn_in.uop.valb_sel && reg_imm.set_nzcv)) begin
                flags[0] = result_final[63];               // N
                flags[1] = (result_final == 64'd0);        // Z
                flags[2] = nzcv_in[2];
                flags[3] = nzcv_in[3];
                case (insn_in.uop.uopcode)
                    UOP_ADD: begin
                        flags[2] = (result_final < r1); // C
                        flags[3] = (~(r1[63] ^ r2[63]) & (r1[63] ^ result_final[63])); // V
                    end
                    UOP_SUB: begin
                        flags[2] = (r1 >= r2);          // C
                        flags[3] = ((r1[63] ^ r2[63]) & (r1[63] ^ result_final[63])); // V
                        $display("SUB: %0d - %0d = %0d, Z: %0d, N: %0d", r1, r2, result_final, flags[1], flags[0]);
                    end
                endcase
                nzcv_out = '{valid: 1'b1, nzcv: flags, index_in: insn_in.nzcv_reg_phys};
            end
            writeback_out = '{valid: 1'b1, ptr: insn_in.ptr, status: DONE};
        end
    end
endmodule
