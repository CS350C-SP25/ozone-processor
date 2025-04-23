`include "../../util/uop_pkg.sv"
`include "../packages/rob_pkg.sv"
`include "../packages/is_pkg.sv"
`include "../../fpu/fpmult.sv"
`include "../../fpu/fpadder.sv"

import uop_pkg::*;
import reg_pkg::*;
import rob_pkg::*;
import is_pkg::*;

module bru_ins_decoder (

    // From ROB
    input  exec_packet insn_in,

    // Current PC
    input  logic [63:0] curr_pc,

    // ALU flags (optional simplification for EQ/NE)
    input  logic [3:0] NZCV_flags,

    // Outputs to ROB / frontend
    output logic ready_out,
    output logic branch_taken,
    output logic [18:0] branch_offset,

    // Only used for BL (writing return addr)
    output RegFileWritePort reg_pkt_out
);

    logic is_bcond, is_bl;
    assign is_bcond = insn_in.uop.uopcode == UOP_BCOND;
    assign is_bl    = insn_in.uop.uopcode == UOP_BL;

    logic [18:0] offset = $signed(insn_in.r2_val) << 2; // Shift left by 2 for ARM instruction set
    logic [3:0] cond    = insn_in.uop.data.condition;
    logic flag_Z, flag_N, flag_V;
    assign flag_Z = NZCV_flags[1];
    assign flag_N = NZCV_flags[0];     
    assign flag_V = NZCV_flags[3];
    // Condition decoding (simplified)
    function logic cond_passed(input logic [3:0] cond);
        case (cond)
            4'b0000: return flag_Z;          // EQ
            4'b0001: return ~flag_Z;         // NE
            4'b1010: return ~(flag_N ^ flag_V); // GE
            4'b1011: return  (flag_N ^ flag_V); // LT
            4'b1100: return ~flag_Z & ~(flag_N ^ flag_V); // GT
            4'b1101: return  flag_Z | (flag_N ^ flag_V);  // LE
            default: return 1'b0; // Unsupported → not taken
        endcase
    endfunction

    always_comb begin
        reg_pkt_out = '0;
        branch_taken = 0;
        branch_offset = '0;
        ready_out = insn_in.valid;

        if (insn_in.valid && is_bl) begin
            branch_taken = 1;
            branch_offset = offset;

            // Write return address to X30
            reg_pkt_out.index_in = insn_in.dest_reg_phys; // this register should be mapped to X30 in the RAT. 
            reg_pkt_out.data_in  = curr_pc + 4;
            reg_pkt_out.en       = 1;

        end else if (insn_in.valid && is_bcond) begin
            branch_taken = cond_passed(cond);
            branch_offset = branch_taken ? offset : 19'b0100;

            // We will handle mispredictions in the ROB
        end
    end

endmodule
