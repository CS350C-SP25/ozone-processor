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
    logic sf; //may be unused (size for W vs X or F vs D)
} uop_reg;

/* Instruction Types */
// register, register uop (25 width)
typedef struct packed {
    uop_reg dst;
    uop_reg src1;
    uop_reg src2;
    logic set_nzcv;
} uop_rr;

// register immediate uop (33 width)
typedef struct packed {
    uop_reg dst;
    uop_reg src;
    logic [15:0] imm;
    logic set_nzcv;
} uop_ri;

// branch uop (69 width)
typedef struct packed {
    logic [63:0] not_taken; // the path not taken in case we mispredict
    logic [3:0] condition;
    logic predict_taken; //true or false
} uop_branch;

/* A Micro-Op Instruction */
// Transaction bits help with maintaining precise exceptions while
// cracking. There are other methods of maintaining precise exceptions
typedef struct packed {
    uop_code uopcode;
    union packed {
        uop_rr rr;
        uop_ri ri;
        uop_branch branch;
    } data;
    logic tx_begin;
    logic tx_end;
} uop_insn;

module instruction_queue #(parameter Q_DEPTH = 32) 
(
    input logic clk_in,
    input logic rst_N_in,
    input logic flush_in,
    input uop_insn q_in;
    input logic enq_in;
    output uop_insn q_out;
    output logic deq_out;
    output logic full;
    output logic empty;
); 
    uop_insn [Q_DEPTH-1:0] q;
    logic [$clog2(Q_DEPTH)-1:0] head;
    logic [$clog2(Q_DEPTH)-1:0] tail;
    always_ff @( posedge clk_in ) begin : instruction_queue_fsm
        
    end

    always_comb begin : instruction_queue_next_state
        
    end
endmodule