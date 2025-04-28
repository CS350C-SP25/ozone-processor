`include "./registers/rat.sv"
`include "./registers/rrat.sv"
`include "./registers/frl.sv"
`include "./registers/reg_file.sv"
`include "./packages/rob_pkg.sv"
`include "./insn_ds/reorder_buffer.sv"
`include "./exec/alu_ins_decoder.sv"
`include "./exec/fpu_ins_decoder.sv"
`include "./exec/lsu_ins_decoder.sv"
`include "./exec/bru_ins_decoder.sv"

import rob_pkg::*;

module backend (
    input logic clk_in,
    input logic rst_N_in,
    input uop_pkg::instr_queue_t instr_queue,

    // ** Signals to Branch Predictor **
    output logic bcond_resolved_out,
    output logic pc_incorrect_out,  // this means that the PC that we had originally predicted was incorrect. We need to fix.
    output logic taken_out,  // if the branch resolved as taken or not -- to update PHT and GHR
    output logic [63:0] pc_out, // pc that is currently in the exec phase (the one that just was resolved)
    output logic [18:0] correction_offset_out, // the offset of the correction from x_pc (could change this to be just the actual correct PC instead ??)
    output logic ready_out  // this is the ready signal for the backend to send to the fetch stage
);

  // Interconnect signals (a subset, connect as needed)

  logic [uop_pkg::INSTR_Q_WIDTH-1:0] rrat_update_valid;
  rob_pkg::rob_entry [uop_pkg::INSTR_Q_WIDTH-1:0] rrat_update_entries;

  logic [3*uop_pkg::INSTR_Q_WIDTH-1:0][$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] frl_registers;
  logic [3*uop_pkg::INSTR_Q_WIDTH-1:0] frl_ready;
  logic frl_valid;

  logic [3*uop_pkg::INSTR_Q_WIDTH-1:0][$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] rrat_free_regs;
  logic [3*uop_pkg::INSTR_Q_WIDTH-1:0] rrat_free_valid;

  logic [15:0] read_en;
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] read_index[15:0];
  logic [reg_pkg::WORD_SIZE-1:0] read_data[15:0];

  // ROB <-> Scheduler signals (can be broken out further)
  rob_pkg::rob_issue alu_insn, fpu_insn, lsu_insn, bru_insn;
  is_pkg::exec_packet alu_insn_pkt, fpu_insn_pkt, lsu_insn_pkt, bru_insn_pkt;
  rob_pkg::rob_writeback alu_wb_out, fpu_wb_out, lsu_wb_out, bru_wb_out;
  logic alu_ready, fpu_ready, lsu_ready, bru_ready;
  logic [reg_pkg::NUM_PHYS_REGS-1:0] scoreboard;
  logic rob_ready_out;

  rob_bru bru_writeback_out;
  rob_bru bru_writeback_in;
  logic bru_wb_valid_out;
  logic bru_wb_valid_in;
  logic [$clog2(rob_pkg::ROB_ENTRIES)-1:0] bru_wb_ptr_in;

  assign bru_wb_valid_in = bru_writeback_in.bcond_resolved_out;
  assign bru_wb_ptr_in = bru_insn_pkt.ptr;

  assign ready_out = rob_ready_out && frl_valid;

  assign read_en = {
    {4{alu_insn.valid}}, {3{fpu_insn.valid}}, 1'b0, {3{lsu_insn.valid}}, 1'b0, {4{bru_insn.valid}}
  };
  assign read_index = {
    alu_insn.dest_reg_phys,
    alu_insn.r1_reg_phys,
    alu_insn.r2_reg_phys,
    alu_insn.nzcv_reg_phys,
    fpu_insn.dest_reg_phys,
    fpu_insn.r1_reg_phys,
    fpu_insn.r2_reg_phys,
    fpu_insn.nzcv_reg_phys,
    lsu_insn.dest_reg_phys,
    lsu_insn.r1_reg_phys,
    lsu_insn.r2_reg_phys,
    lsu_insn.nzcv_reg_phys,
    bru_insn.dest_reg_phys,
    bru_insn.r1_reg_phys,
    bru_insn.r2_reg_phys,
    bru_insn.nzcv_reg_phys
  };
  assign alu_insn_pkt = {
    alu_insn.valid,
    alu_insn.uop,
    alu_insn.ptr,
    alu_insn.dest_reg_phys,
    alu_insn.nzcv_reg_phys,
    read_data[15],
    read_data[14],
    read_data[13]
  };
  assign fpu_insn_pkt = {
    fpu_insn.valid,
    fpu_insn.uop,
    fpu_insn.ptr,
    fpu_insn.dest_reg_phys,
    fpu_insn.nzcv_reg_phys,
    read_data[11],
    read_data[10],
    read_data[9]
  };
  assign lsu_insn_pkt = {
    lsu_insn.valid,
    lsu_insn.uop,
    lsu_insn.ptr,
    lsu_insn.dest_reg_phys,
    lsu_insn.nzcv_reg_phys,
    read_data[7],
    read_data[6],
    read_data[5]
  };
  assign bru_insn_pkt = {
    bru_insn.valid,
    bru_insn.uop,
    bru_insn.ptr,
    bru_insn.dest_reg_phys,
    bru_insn.nzcv_reg_phys,
    read_data[3],
    read_data[2],
    read_data[1]
  };

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
  logic rat_q_ready;
  rob_pkg::rob_entry [uop_pkg::INSTR_Q_WIDTH-1:0] rob_entries_out;
  logic rob_data_valid;
  logic rob_ready;
  reg_pkg::RegFileWritePort [uop_pkg::INSTR_Q_WIDTH-1:0] regfile_ports;

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
      .clk_in(clk_in),
      .rst_N_in(rst_N_in),
      .q_in(rob_entries_out),
      .flush_in(1'b0),

      .alu_ready_in(alu_ready),
      .fpu_ready_in(fpu_ready),
      .lsu_ready_in(lsu_ready),
      .bru_ready_in(bru_ready),
      .writeback_in('{alu_wb_out, lsu_wb_out, bru_wb_out, fpu_wb_out}),
      .scoreboard_in(scoreboard),
      .bru_writeback_in(bru_writeback_in),
      .bru_wb_valid_in(bru_wb_valid_in),
      .bru_wb_ptr_in(bru_wb_ptr_in),

      .alu_insn_out(alu_insn),
      .fpu_insn_out(fpu_insn),
      .lsu_insn_out(lsu_insn),
      .bru_insn_out(bru_insn),
      .rrat_update_out(rrat_update_entries),
      .rrat_update_valid_out(rrat_update_valid),
      .bru_writeback_out(bru_writeback_out),
      .bru_wb_valid_out(bru_wb_valid_out),
      .rob_ready_out(rob_ready_out)
  );

  // ALU
  RegFileWritePort alu_reg_pkt;
  NZCVWritePort alu_nzcv;
  logic [3:0] alu_nzcv_flags;
  assign alu_nzcv_flags = read_data[12][3:0];  // NZCV flags from the register file

  alu_ins_decoder alu_decoder (
      .clk_in(clk_in),
      .insn_in(alu_insn_pkt),
      .nzcv_in(alu_nzcv_flags),
      .ready_out(alu_ready),
      .reg_pkt_out(alu_reg_pkt),
      .nzcv_out(alu_nzcv),
      .writeback_out(alu_wb_out)
  );

  // FPU
  RegFileWritePort fpu_reg_pkt;
  logic [reg_pkg::WORD_SIZE-1:0] fpmult_result, fpadder_result;
  logic [reg_pkg::WORD_SIZE-1:0] fpu_a_out;
  logic [reg_pkg::WORD_SIZE-1:0] fpu_b_out;
  logic fpmult_valid_out, fpadder_valid_out;
  logic fpmult_result_valid, fpadder_result_valid;

  fpu_ins_decoder fpu_decoder (
      .clk_in(clk_in),
      .rst_N_in(rst_N_in),
      .flush_in(1'b0),
      .insn_in(fpu_insn_pkt),
      .fpu_result(fpmult_result_valid ? fpmult_result : fpadder_result),
      .fpu_valid(fpmult_result_valid | fpadder_result_valid),
      .ready_out(fpu_ready),
      .reg_pkt_out(fpu_reg_pkt),
      .fpu_a_out(fpu_a_out),
      .fpu_b_out(fpu_b_out),
      .fpmult_valid_out(fpmult_valid_out),
      .fpadder_valid_out(fpadder_valid_out),
      .writeback_out(fpu_wb_out)
  );

  fpadder #(
      .EXPONENT_WIDTH(11),
      .MANTISSA_WIDTH(52),
      .ROUND_TO_NEAREST_TIES_TO_EVEN(1),  // 0: round to zero (chopping last bits), 1: round to nearest
      .IGNORE_SIGN_BIT_FOR_NAN(1)
  ) fpadder_inst (
      .a(fpu_a_out),
      .b(fpu_b_out),
      .valid_in(fpadder_valid_out),
      .subtract('0),

      // Output signals
      .out(fpadder_result),
      .valid_out(fpadder_result_valid),
      .underflow_flag(),
      .overflow_flag(),
      .invalid_operation_flag()
  );

  fpmult_rtl #(
      .P(53),
      .Q(11)
  ) fpmult_rtl_inst (
      .rst_in_N(rst_N_in),            // asynchronous active-low reset
      .clk_in  (clk_in),              // clock
      .x_in    (fpu_a_out),           // input X; x_in[15] is the sign bit
      .y_in    (fpu_b_out),           // input Y: y_in[15] is the sign bit
      .round_in(1),                   // rounding mode specifier
      .start_in(fpmult_valid_out),    // signal to start multiplication
      .p_out   (fpmult_result),       // output P: p_out[15] is the sign bit
      .oor_out (),                    // out-of-range indicator vector
      .done_out(fpmult_result_valid)  // signal that outputs are ready
  );

  // LSU
  RegFileWritePort lsu_reg_pkt;

  lsu_ins_decoder lsu_decoder (
      .clk_in(clk_in),
      .rst_N_in(rst_N_in),
      .flush_in(1'b0),
      .insn_in(lsu_insn_pkt),
      .mem_data_in(64'b0),  // stub for now
      .mem_resp_tag(0),
      .mem_valid_in(0),
      .mem_addr_out(),
      .mem_tag_out(),
      .mem_valid_out(),
      .reg_pkt_out(lsu_reg_pkt),
      .ready_out(lsu_ready),
      .writeback_out(lsu_wb_out)
  );

  // BRU
  RegFileWritePort bru_reg_pkt;
  logic [18:0] branch_offset;
  logic branch_taken;
  logic [3:0] bru_nzcv_flags;
  assign bru_writeback_in.taken_out = branch_taken;
  assign bru_writeback_in.pc_out = bru_insn_pkt.uop.pc;
  assign bru_writeback_in.correction_offset_out = branch_offset;
  assign bru_writeback_in.pc_incorrect_out = bru_insn_pkt.uop.data.predict_taken != branch_taken;
  assign bru_writeback_in.bcond_resolved_out = bru_insn_pkt.valid;
  assign bru_nzcv_flags = read_data[15][3:0];  // NZCV flags from the register file

  assign taken_out = bru_writeback_out.taken_out;
  assign pc_out = bru_writeback_out.pc_out;
  assign correction_offset_out = bru_writeback_out.correction_offset_out;
  assign pc_incorrect_out = bru_writeback_out.pc_incorrect_out;
  assign bcond_resolved_out = bru_writeback_out.bcond_resolved_out;


  bru_ins_decoder bru_decoder (
      .insn_in(bru_insn_pkt),
      .curr_pc(64'h0),  // stub
      .NZCV_flags(bru_nzcv_flags),
      .ready_out(bru_ready),
      .branch_taken(branch_taken),
      .branch_offset(branch_offset),
      .reg_pkt_out(bru_reg_pkt),
      .writeback_out(bru_wb_out)
  );

  // Regfile (stub wiring)
  reg_file #(
      .NUM_READ_PORTS (16),  // 4 functional units * 4 (rd, r1, r2, nzcv) registers
      .NUM_WRITE_PORTS(8)    // 4 functional units for dest regs
  ) regfile_inst (
      .clk(clk_in),
      .rst(rst_N_in),
      .read_en(read_en),
      .read_index(read_index),
      .read_data(read_data),
      .scoreboard(scoreboard),
      .write_ports(
      '{
          alu_reg_pkt,
          fpu_reg_pkt,
          lsu_reg_pkt,
          bru_reg_pkt,
          regfile_ports[0],
          regfile_ports[1],
          regfile_ports[2],
          regfile_ports[3]
      }
      ),
      .nzcv_write_port(alu_nzcv)
  );

endmodule
