import uop_pkg::*;
import reg_pkg::*;
import rob_pkg::*;

package is_pkg;
    parameter int NUM_LSU = 1;
    parameter int NUM_BRU = 1;
    parameter int NUM_ALU = 1;
    parameter int NUM_FPU = 1;
    
    parameter int FQ_EL_SIZE = $bits(rob_issue);
    parameter int FQ_ENTRIES = ROB_ENTRIES / 4;

    typedef enum logic [1:0] {
        WAITING,
        IN_QUEUE,
        ISSUED
    } instr_status;

endpackage