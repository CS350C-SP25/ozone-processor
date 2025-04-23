`include "../../util/uop_pkg.sv"
`include "./reg_pkg.sv"
`include "./rob_pkg.sv"

import uop_pkg::*;
import reg_pkg::*;
import rob_pkg::*;

package is_pkg;
    parameter int NUM_LSU = 1;
    parameter int NUM_BRU = 1;
    parameter int NUM_ALU = 1;
    parameter int NUM_FPU = 1;
    parameter int NUM_FUNC_UNITS = 1;

    parameter int FQ_EL_SIZE = $bits(rob_issue);
    parameter int FQ_ENTRIES = ROB_ENTRIES / 4;

    typedef struct packed {
        logic valid;
        uop_insn uop;
        logic [$clog2(ROB_ENTRIES)-1:0] ptr; // ptr to entry in the ROB
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] dest_reg_phys; // forward these values from ROB to save on wires
        logic [reg_pkg::WORD_SIZE-1:0] r0_val;
        logic [reg_pkg::WORD_SIZE-1:0] r1_val;
        logic [reg_pkg::WORD_SIZE-1:0] r2_val;
    } exec_packet; // struct for issuing insn to execute
endpackage