`timescale 1ns/1ps

package uop_pkg;

    // Parameters for queue depth/width
    /* verilator lint_off UNUSEDPARAM */
    parameter int INSTR_Q_DEPTH = 32;
    parameter int INSTR_Q_WIDTH = 5;
    /* verilator lint_on UNUSEDPARAM */

    typedef enum logic[4:0] {
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
        UOP_ASR,
        UOP_BCOND,
        UOP_BL,
        UOP_MOVZ,
        UOP_MOVK,
        UOP_FMOV,
        UOP_FNEG,
        UOP_FADD,
        UOP_FMUL,
        UOP_FSUB,
        UOP_CHECK_RET,
        UOP_ADRP_MOV,
        UOP_HLT // NOPS wont be sent at all, HLT is exception will need.
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
        logic [20:0] imm;
        logic [1:0] hw;
        logic set_nzcv;
    } uop_ri;

    typedef struct packed {
        logic [63:0] branch_target;
        logic [3:0] condition;
        logic predict_taken;
    } uop_branch;

    typedef struct packed { // changed it so it will compile for ROB for now, feel free to change later
        uop_code uopcode;
        uop_branch data; //this is actually going to be a union, quartus doesnt support unions
        logic [63:0] pc; // left undetermined if non PC operation. PC operations are B BCOND, BL, RET, ADRP
        logic valb_sel; // use val b or immediate
        logic mem_read;
        logic mem_write;
        logic w_enable;
        logic tx_begin;
        logic tx_end;
    } uop_insn;

    function automatic void get_data_rr (
        /* verilator lint_off UNUSEDSIGNAL */
        input logic[$bits(uop_branch)-1:0] in,
        /* verilator lint_on UNUSEDSIGNAL */
        output uop_rr out
    );
        out = in[$bits(uop_rr)-1:0];
    endfunction

    function automatic void set_data_rr (
        input  uop_rr in,
        output logic [$bits(uop_branch)-1:0] out
    );
        out = { {($bits(uop_branch)-$bits(uop_rr)){1'b0}}, in };
    endfunction

    function automatic void get_data_ri (
        /* verilator lint_off UNUSEDSIGNAL */
        input logic[$bits(uop_branch)-1:0] in,
        /* verilator lint_on UNUSEDSIGNAL */
        output uop_ri out
    );
        out = in[$bits(uop_ri)-1:0];
    endfunction

    function automatic void set_data_ri (
        input  uop_ri in,
        output logic [$bits(uop_branch)-1:0] out
    );
        out = { {($bits(uop_branch)-$bits(uop_ri)){1'b0}}, in };
    endfunction

    function automatic void get_data_br (
        input logic[$bits(uop_branch)-1:0] in,
        output uop_branch out
    );
        out = in;
    endfunction

    function automatic void set_data_br (
        input uop_branch in,
        output logic[$bits(uop_branch)-1:0] out
    );
        out = in;
    endfunction
endpackage
