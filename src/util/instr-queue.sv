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

module instruction_queue #(
    parameter Q_DEPTH = 32,
    parameter Q_WIDTH = 2
) 
(
    input logic clk_in,
    input logic rst_N_in,                       // resets the q completely, empty, 0 size, etc.
    input logic flush_in,                       // same function as reset
    input uop_insn [Q_WIDTH-1:0] q_in;
    input logic [$clog2(Q_WIDTH+1)-1:0] enq_in; // how many to push IMPORTANT, IT IS ENQERS JOB TO DETERMINE HOW MANY IS SAFE TO ENQ
    input logic [$clog2(Q_WIDTH+1)-1:0] deq_in; // how many to pop IMPORTANT, IT IS DEQERS JOB TO DETERMINE HOW MANY IS SAFE TO DEQ (USE SIZE)

    output uop_insn [Q_WIDTH-1:0] q_out;        // the top width elements of the queue
    output logic full;                          // 1 if the queue is full
    output logic empty;                         // 1 if the queue is empty
    output logic [$clog2(Q_DEPTH)-1:0] size;    // the #elems in the queue
); 
    uop_insn [Q_DEPTH-1:0] q;
    logic [$clog2(Q_DEPTH)-1:0] head;
    logic [$clog2(Q_DEPTH)-1:0] tail;

    uop_insn [Q_WIDTH-1:0] q_next;
    logic [$clog2(Q_WIDTH+1)-1:0] size_incr;
    logic [$clog2(Q_WIDTH+1)-1:0] size_decr; 
    always_ff @( posedge clk_in ) begin : instruction_queue_fsm
        if (rst_N_in && !flush_in) begin
            generate
                for (genvar i = 0; i < Q_WIDTH; i++) begin
                    q[tail + i] <= size_incr > i ? q_next[i] : q[tail];
                end
            endgenerate
            head <= head + size_decr;
            tail <= tail + size_incr;
            size <= tail - head + size_incr - size_decr;
        end else begin
            head <= '0;
            tail <= '0;
            size <= '0;
        end
    end

    always_comb begin : instruction_queue_next_state
        q_next = q_in;
        size_incr = flush_in ? 0 : enq_in;
        size_decr = flush_in ? tail - head : deq_in;
    end
    generate
        for (genvar i = 0; i < Q_WIDTH; i++) begin
            assign q_out[i] <= q[head + i];
        end
    endgenerate
    assign full = (size == Q_DEPTH);
    assign empty = (size == 0);
endmodule