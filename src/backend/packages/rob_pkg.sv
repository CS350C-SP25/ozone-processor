`ifndef ROB_PKG_SV
`define ROB_PKG_SV
`include "../../util/uop_pkg.sv"
`include "./reg_pkg.sv"


package rob_pkg;
import uop_pkg::*;
import reg_pkg::*;


    parameter int ROB_ENTRIES = 32;

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
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] nzcv_reg_phys; // To operate on
        logic [1:0][$clog2(ROB_ENTRIES):0] dependent_entries; // there are 2 possible insn/regs that the uop can be dependent on. these will be stored as idxes in the ROB. 
        status_t status;
    } rob_entry;

    typedef struct packed {
        logic valid;
        uop_insn uop;
        logic [$clog2(ROB_ENTRIES)-1:0] ptr; // ptr to entry in the ROB
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] dest_reg_phys; // forward these values from ROB to save on wires
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] r1_reg_phys; // To operate on
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] r2_reg_phys; // To operate on
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] nzcv_reg_phys; // To operate on
    } rob_issue; // struct for issuing insn from the ROB

    typedef struct packed {
        logic valid;
        logic [$clog2(ROB_ENTRIES)-1:0] ptr; // ptr to entry in the ROB
        status_t status;
    } rob_writeback; // struct for writing back data to the ROB

    typedef struct packed {
        logic bcond_resolved_out;
        logic pc_incorrect_out;  // this means that the PC that we had originally predicted was incorrect. We need to fix.
        logic taken_out;  // if the branch resolved as taken or not -- to update PHT and GHR
        logic [63:0] pc_out; // pc that is currently in the exec phase (the one that just was resolved)
        logic [18:0] correction_offset_out;
    } rob_bru; // struct for writing back data to the ROB
endpackage
`endif // ROB_PKG_SV
