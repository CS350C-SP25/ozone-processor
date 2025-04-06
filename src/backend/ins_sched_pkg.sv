import uop_pkg::*;
import reg_pkg::*;

package ins_sched_pkg;

    paramater int IS_ENTIRES = 64; // TODO

    typedef enum logic [2:0] {
        WAITING,
        READY,
        ISSUED,
        DONE,
        EXCEPTION
    } is_status;

    /* Instruction scheduler queue entry */
    typedef struct packed {
        logic [reg_pkg::ADDR_BITS-1:0] pc;
        uop_insn uop;
        is_status status;
    } is_entry;

    /* Ready queue entry */
    typedef struct packed {
        logic [reg_pkg::ADDR_BITS-1:0] pc;
        uop_insn uop;
        is_status status;
    } rq_entry;

    // issue packet TODO

endpackage