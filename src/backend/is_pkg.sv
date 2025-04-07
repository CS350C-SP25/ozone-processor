import uop_pkg::*;
import reg_pkg::*;

package is_pkg;

    parameter int IS_ENTRIES = 128; // TODO
    parameter int RQ_ENTRIES = IS_ENTRIES;

    typedef enum logic [2:0] {
        IS_WAITING,
        IS_READY,
        IS_ISSUED,
        IS_DONE,
        IS_EXCEPTION
    } is_status;

    typedef enum logic [1:0] {
        OP_WAITING,
        OP_READY,
        OP_EXCEPTION
    } op_status;

    /* Instruction scheduler queue entry */
    typedef struct packed {
        logic [reg_pkg::ADDR_BITS-1:0] pc;
        uop_insn uop;
        is_status status;
        logic [$clog2(rob_pkg::ROB_ENTRIES)-1:0] rob_entry;
        logic [$clog2(reg_pkg::NUM_ARCH_REGS)-1:0] dest_reg;
        logic [1:0][reg_pkg::ADDR_BITS-1:0] operands;
        op_status [1:0] operand_status;
        //logic [reg_pkg::ADDR_BITS-1:0] result_value;
    } is_entry;

    /* Ready queue entry */
    typedef struct packed {
        logic [reg_pkg::ADDR_BITS-1:0] pc;
        uop_insn uop;
        is_status status;
        logic [$clog2(rob_pkg::ROB_ENTRIES)-1:0] rob_entry;
        logic [$clog2(reg_pkg::NUM_ARCH_REGS)-1:0] dest_reg;
        logic [reg_pkg::ADDR_BITS-1:0] result_value;
    } rq_entry;

    // issue packet
    typedef struct packed {
        uop_insn uop;
        logic [$clog2(IS_ENTRIES)-1:0] ptr;
    } is_issue;

endpackage