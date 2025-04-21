`include "../util/uop_pkg.sv"
`include "../backend/reg_pkg.sv"

import uop_pkg::*;
import reg_pkg::*;

package rob_pkg;
    parameter int ROB_ENTRIES = 256;

    typedef enum logic [2:0] {
        ISSUED = 3'b000,
        DONE = 3'b001,
        EXCEPTION = 3'b010,
        INTERRUPT = 3'b011,
        TRAP = 3'b100
    } status_t;

    typedef struct packed {
        logic [reg_pkg::ADDR_BITS-1:0] pc;
        logic [reg_pkg::ADDR_BITS-1:0] next_pc;
        uop_insn uop;
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] r1_reg_phys; // To operate on
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] r2_reg_phys; // To operate on
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] dest_reg_phys; // To operate on
        status_t status;
    } rob_entry;
endpackage
