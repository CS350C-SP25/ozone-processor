package uop_pkg;

    // Parameters for queue depth/width
    parameter int INSTR_Q_DEPTH = 32;
    parameter int INSTR_Q_WIDTH = 4;

    typedef enum logic[3:0] {
        UOP_LOAD,
        UOP_STORE,
        UOP_ADD,
        UOP_SUB,
        UOP_AND,
        UOP_ORR,
        UOP_XOR,
        UOP_EOR,
        UOP_MVN,
        UOP_UBFM,
        UOP_BRANCH,
        UOP_NOP
    } uop_code;

    typedef struct packed {
        logic [4:0] gpr;
        logic is_sp;
        logic is_fp;
        // No SF bit we are only X registers.
    } uop_reg;

    typedef struct packed {
        uop_reg dst;
        uop_reg src1;
        uop_reg src2;
        logic set_nzcv;
    } uop_rr;

    typedef struct packed {
        uop_reg dst;
        uop_reg src;
        logic [15:0] imm;
        logic set_nzcv;
    } uop_ri;

    typedef struct packed {
        logic [63:0] not_taken;
        logic [3:0] condition;
        logic predict_taken;
    } uop_branch;

    typedef struct packed { // changed it so it will compile for ROB for now, feel free to change later
        uop_code uopcode;
        // union packed {
        //     uop_rr rr;
        //     uop_ri ri;
        //     uop_branch branch;
        // } data;
        uop_rr data;
        logic valb_sel; // use val b or immediate
        logic mem_read;
        logic mem_write;
        logic w_enable;
        logic tx_begin;
        logic tx_end;
    } uop_insn;
endpackage
