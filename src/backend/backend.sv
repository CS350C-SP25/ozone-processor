`include "./registers/rat.sv"
`include "./registers/rrat.sv"
`include "./registers/frl.sv"
`include "./registers/reg_file.sv"
`include "./packages/rob_pkg"
`include "./insn_ds/reorder_buffer.sv"
`include "./exec/alu_ins_decoder.sv"
`include "./exec/fpu_ins_decoder.sv"
`include "./exec/lsu_ins_decoder.sv"
`include "./exec/bru_ins_decoder.sv"

import rob_pkg::*;

module backend(
    input logic clk_in,
    input logic rst_N_in
);

    // Interconnect signals (a subset, connect as needed)

    logic [1:0] rrat_update_valid;
    rob_pkg::rob_entry [1:0] rrat_update_entries;

    logic [3:0][$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] frl_registers;
    logic [3:0] frl_ready;
    logic frl_valid;

    logic [5:0][$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] rrat_free_regs;
    logic [5:0] rrat_free_valid;

    logic [3:0] read_en;
    logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] read_index[3:0];
    logic [reg_pkg::WORD_SIZE-1:0] read_data[3:0];

    // ROB <-> Scheduler signals (can be broken out further)
    rob_pkg::rob_issue alu_insn, fpu_insn, lsu_insn, bru_insn;
    logic alu_ready, fpu_ready, lsu_ready, bru_ready;

    // RRAT
    rrat rrat_inst (
        .clk(clk_in),
        .rst(rst_N_in),
        .rob_entry_valid(rrat_update_valid),
        .rob_data(rrat_update_entries),
        .free_registers_valid_out(rrat_free_valid),
        .register_mappings(rrat_free_regs)
    );

    // FRL
    frl frl_inst (
        .clk(clk_in),
        .rst(rst_N_in),
        .acquire_ready_in(frl_ready),
        .acquire_valid_out(frl_valid),
        .registers_out(frl_registers),
        .free_valid_in(rrat_free_valid),
        .freeing_registers(rrat_free_regs)
    );

    // RAT
    logic q_valid;
    uop_pkg::uop_insn [1:0] instr_queue;
    logic rat_q_ready;
    rob_pkg::rob_entry [1:0] rob_entries_out;
    logic rob_data_valid;
    logic rob_ready;
    reg_pkg::RegFileWritePort [1:0] regfile_ports;

    rat rat_inst (
        .clk(clk_in),
        .rst_N_in(rst_N_in),
        .q_valid(q_valid),
        .instr(instr_queue),
        .q_increment_ready(rat_q_ready),
        .rob_data(rob_entries_out),
        .rob_data_valid(rob_data_valid),
        .rob_ready(rob_ready),
        .frl_ready(frl_ready),
        .free_register_data(frl_registers),
        .frl_valid(frl_valid),
        .regfile(regfile_ports)
    );

    // Reorder Buffer
    reorder_buffer rob_inst (
        .clk_in(clk),
        .rst_N_in(rst_N_in),
        .flush_in(1'b0),
        .alu_ready_in(alu_ready),
        .fpu_ready_in(fpu_ready),
        .lsu_ready_in(lsu_ready),
        .bru_ready_in(bru_ready),
        .alu_insn_out(alu_insn),
        .fpu_insn_out(fpu_insn),
        .lsu_insn_out(lsu_insn),
        .bru_insn_out(bru_insn),
        .rrat_update_out(rrat_update_entries),
        .rrat_update_valid_out(rrat_update_valid)
        // + other inputs/outputs as needed
    );

    // ALU
    logic alu_ready_out;
    RegFileWritePort alu_reg_pkt;
    NZCVWritePort alu_nzcv;

    alu_ins_decoder alu_decoder (
        .clk_in(clk),
        .insn_in(alu_insn),
        .ready_out(alu_ready),
        .reg_pkt_out(alu_reg_pkt),
        .nzcv_out(alu_nzcv)
    );

    // FPU
    RegFileWritePort fpu_reg_pkt;
    logic [reg_pkg::WORD_SIZE-1:0] fpu_result;
    logic [reg_pkg::WORD_SIZE-1:0] fpu_a_out;
    logic [reg_pkg::WORD_SIZE-1:0] fpu_b_out;
    logic fpmult_valid_out, fpadder_valid_out;

    fpu_ins_decoder fpu_decoder (
        .clk_in(clk),
        .rst_N_in(rst_N_in),
        .flush_in(1'b0),
        .insn_in(fpu_insn),
        .fpu_result(fpu_result),
        .fpu_valid(fpu_result_valid),
        .ready_out(fpu_ready),
        .reg_pkt_out(fpu_reg_pkt),
        .fpu_a_out(fpu_a_out),
        .fpu_b_out(fpu_b_out),
        .fpmult_valid_out(fpmult_valid_out),
        .fpadder_valid_out(fpadder_valid_out)
    );

    fpadder #(
        .EXPONENT_WIDTH(11),
        .MANTISSA_WIDTH(52),
        .ROUND_TO_NEAREST_TIES_TO_EVEN(1),  // 0: round to zero (chopping last bits), 1: round to nearest
        .IGNORE_SIGN_BIT_FOR_NAN(1)
    ) fpadder_inst (
        .a(fpu_a_out),
        .b(fpu_b_out),
        .out(fpu_result),

        // Subtraction flag
        .subtract('0),
        // Output exception flags
        .underflow_flag(),
        .overflow_flag(),
        .invalid_operation_flag()
    );

    fpmult_rtl #(.P(52), .Q(11))
    fpmult_rtl_inst(
        .rst_in_N(rst_N_in),        // asynchronous active-low reset
        .clk_in(clk_in),          // clock
        .x_in(fpu_a_out),     // input X; x_in[15] is the sign bit
        .y_in(fpu_b_out),     // input Y: y_in[15] is the sign bit
        .round_in(1),  // rounding mode specifier
        .start_in(fpmult_valid_out),        // signal to start multiplication
        .p_out(fpu_result),  // output P: p_out[15] is the sign bit
        .oor_out(), // out-of-range indicator vector
        .done_out(fpu_result_valid)       // signal that outputs are ready
    );

    // LSU
    RegFileWritePort lsu_reg_pkt;

    lsu_ins_decoder lsu_decoder (
        .clk_in(clk),
        .rst_N_in(~rst),
        .flush_in(1'b0),
        .insn_in(lsu_insn),
        .mem_data_in(64'b0), // stub for now
        .mem_resp_tag(0),
        .mem_valid_in(0),
        .mem_addr_out(),
        .mem_tag_out(),
        .mem_valid_out(),
        .reg_pkt_out(lsu_reg_pkt),
        .ready_out(lsu_ready)
    );

    // BRU
    RegFileWritePort bru_reg_pkt;
    logic [63:0] branch_target;
    logic branch_taken;
    logic bru_ready_out;

    bru_ins_decoder bru_decoder (
        .insn_in(bru_insn),
        .curr_pc(64'h0), // stub
        .NZCV_flags(alu_nzcv.nzcv),
        .ready_out(bru_ready),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .reg_pkt_out(bru_reg_pkt)
    );

    // Regfile (stub wiring)
    reg_file regfile_inst (
        .clk(clk),
        .rst(rst),
        .read_en(read_en),
        .read_index(read_index),
        .read_data(read_data),
        .write_ports('{alu_reg_pkt, fpu_reg_pkt})
    );

endmodule