`include "./registers/rat.sv"
`include "./registers/rrat.sv"
`include "./packages/rob_pkg"
`include "./insn_ds/reorder_buffer.sv"
`include "./exec/alu_ins_decoder.sv"
`include "./exec/fpu_ins_decoder.sv"
`include "./exec/lsu_ins_decoder.sv"
`include "./exec/bru_ins_decoder.sv"

module backend(
    input logic clk_in,
    input logic rst_N_in,
);
    reorder_buffer #(
    .Q_DEPTH(rob_pkg::ROB_ENTRIES),
    .Q_WIDTH(uop_pkg::INSTR_Q_WIDTH),
    .ADDR_BITS(64),
    .WORD_SIZE(64)
    ) reorder_buffer(
        .clk_in(clk_in),
        .rst_N_in(rst_N_in),
        input rob_entry [Q_WIDTH-1:0] q_in,
        input logic [$clog2(Q_WIDTH+1)-1:0] enq_in,

        // ** INPUTS FROM BRANCH UNIT **
        input logic flush_in, // fed from either RESET or branch misprediction
        input logic [ADDR_BITS-1:0] target_pc, // if branch misprediction, this is the target pc

        // ** INPUTS FROM INSTR_SCHEDULER **
        input logic alu_ready_in,
        input logic fpu_ready_in,
        input logic lsu_ready_in,
        input logic bru_ready_in,

        // ** PC OUTPUT LOGIC **
        output logic valid_pc_out, // if PC needs to be set for exception handling, branch mispredictions, trap, etc..
        output logic [ADDR_BITS-1:0] pc_out,

        // ** STR OUTPUT LOGIC **
        output logic[Q_WIDTH-1:0] valid_str_out, // map of which stores are valid
        output logic [Q_WIDTH-1:0][$clog2(reg_pkg::NUM_ARCH_REGS)-1:0] str_addr_reg_out, // arch reg to load STR addr from
        output logic [Q_WIDTH-1:0][$clog2(reg_pkg::NUM_ARCH_REGS)-1:0] str_addr_reg_off_out, // arch reg to load STR addr from
        output logic [Q_WIDTH-1:0][$clog2(reg_pkg::NUM_ARCH_REGS)-1:0] str_val_reg_out, // arch reg to load STR val from

        // ** EXEC OUTPUT LOGIC **
        // these outputs will be sent to the execute phase where insn scheduler will decide which ones we can execute
        output rob_issue lsu_insn_out,
        output rob_issue bru_insn_out, 
        output rob_issue alu_insn_out, 
        output rob_issue fpu_insn_out,

        output rob_entry [1:0] rrat_update_out, // update the rrat mapping for the physical reg to arch reg mapping
        output logic [1:0] rrat_update_valid_out, // 1 if the rrat update is valid
    );
endmodule: backend