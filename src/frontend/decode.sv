import uop_pkg::*;

module decode #(
    parameter INSTRUCTION_WIDTH = 32;
    parameter SUPER_SCALAR_WIDTH = 2,
    parameter INSTR_Q_DEPTH = uop_pkg::INSTR_Q_DEPTH,
    parameter INSTR_Q_WIDTH = uop_pkg::INSTR_Q_WIDTH
) (
    input logic clk_in,
    input logic rst_N_in,
    input logic flush_in,
    output logic ready,
    output logic valid,
    input logic[SUPER_SCALAR_WIDTH-1:0][INSTRUCTION_WIDTH-1:0] fetched_ops,
    output logic [$clog2(INSTR_Q_WIDTH+1)-1:0] instruction_queue_pushes,
    output uop_insn[INSTR_Q_WIDTH-1:0] instruction_queue_in
);
    uop_insn [INSTR_Q_WIDTH-1:0] enq_next;
    always_ff @(posedge clk_in) begin : decode_fsm
    end

    always_comb begin : decode_comb_logic
        int enq_idx = 0;
        generate
            for (genvar instr_idx = 0; instr_idx < SUPER_SCALAR_WIDTH; instr_idx++) begin : super_scalar_decode
                
            end
        endgenerate

    end

endmodule