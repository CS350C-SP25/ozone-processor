`include "../../util/uop_pkg.sv"
`include "./reg_pkg.sv"


package rob_pkg;
import uop_pkg::*;
import reg_pkg::*;


    parameter int ROB_ENTRIES = 128;

    typedef enum logic [2:0] {
        READY,
        ISSUED,
        DONE,
        EXCEPTION,
        INTERRUPT,
        TRAP
    } status_t;

    typedef struct packed {
        logic [reg_pkg::ADDR_BITS-1:0] pc;
        logic [reg_pkg::ADDR_BITS-1:0] next_pc;
        uop_insn uop;
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] r1_reg_phys; // To operate on
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] r2_reg_phys; // To operate on
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] dest_reg_phys; // To operate on
        logic [1:0][$clog2(ROB_ENTRIES):0] dependent_entries; // there are 2 possible insn/regs that the uop can be dependent on. these will be stored as idxes in the ROB. 
        status_t status;
    } rob_entry;

    typedef struct packed {
        logic valid;
        uop_insn uop;
        logic [$clog2(ROB_ENTRIES)-1:0] ptr; // ptr to entry in the ROB
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] dest_reg_phys; // forward these values from ROB to save on wires
        logic [reg_pkg::WORD_SIZE-1:0] r0_val;
        logic [reg_pkg::WORD_SIZE-1:0] r1_val;
        logic [reg_pkg::WORD_SIZE-1:0] r2_val;
    } rob_issue; // struct for issuing insn from the ROB
endpackage
