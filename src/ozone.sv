`include "./backend/backend.sv"
`include "./frontend/frontend.sv"

module ozone (
    input logic clk_in,
    input logic rst_N_in,
    input logic cs_N_in,
    input logic start,
    input logic [63:0] start_pc,
    input logic lc_ready_in,
    input logic lc_valid_in,
    input logic [63:0] lc_addr_in,
    input logic [511:0] lc_value_in,
    output logic lc_valid_out,
    output logic lc_ready_out,
    output logic [63:0] lc_addr_out,
    output logic [511:0] lc_value_out,
    output logic lc_we_out
);
  logic bcond_resolved_out;
  logic pc_incorrect_out;
  logic taken_out;
  logic [63:0] pc_out;
  logic [18:0] correction_offset_out;
  //   typedef uop_insn instr_queue_t[INSTR_Q_WIDTH-1:0];
  instr_queue_t instruction_queue_in;
  logic exec_ready;

  frontend fe (
      .clk_in(clk_in),
      .rst_N_in(rst_N_in),
      .cs_N_in(cs_N_in),
      .start(start),
      .start_pc(start_pc),
      .x_bcond_resolved(bcond_resolved_out),
      .x_pc_incorrect(pc_incorrect_out),
      .x_taken(taken_out),
      .x_pc(pc_out),
      .x_correction_offset(correction_offset_out),
      .lc_ready_in(lc_ready_in),
      .lc_valid_in(lc_valid_in),
      .lc_addr_in(lc_addr_in),
      .lc_value_in(lc_value_in),
      .exe_ready(exec_ready),
      .lc_valid_out(lc_valid_out),
      .lc_ready_out(lc_ready_out),
      .lc_addr_out(lc_addr_out),
      .lc_value_out(lc_value_out),
      .lc_we_out(lc_we_out),
      .instruction_queue_in(instruction_queue_in)
  );

  backend be (
      .clk_in(clk_in),
      .rst_N_in(rst_N_in),
      .instr_queue(instruction_queue_in),
      .bcond_resolved_out(bcond_resolved_out),
      .pc_incorrect_out(pc_incorrect_out),  // this means that the PC that we had originally predicted was incorrect. We need to fix.
      .taken_out(taken_out),  // if the branch resolved as taken or not -- to update PHT and GHR
      .pc_out(pc_out),  // pc that is currently in the exec phase (the one that just was resolved)
      .correction_offset_out(correction_offset_out), // the offset of the correction from x_pc (could change this to be just the actual correct PC instead ??)
      .ready_out(exec_ready)
  );
  load_store_unit #(
    .QUEUE_DEPTH(32),
    .TAG_WIDTH(10)
  ) lsu(
    // Generic inputs
    input logic clk_in,
    input logic rst_N_in,
    input logic cs_N_in,   // Chip Select (enable signal)

    // Processor Instruction Interface
    input logic proc_instr_valid_in,
    input logic [TAG_WIDTH-1:0] proc_instr_tag_in,
    input logic proc_instr_is_write_in,

    // Processor Data Interface
    input logic proc_data_valid_in,
    input logic [TAG_WIDTH-1:0] proc_data_tag_in,
    input logic [63:0] proc_addr_in,
    input logic [63:0] proc_value_in,

    // L1 Cache (L1D) Interface (inputs)
    input logic l1d_valid_in,
    input logic l1d_ready_in,
    input logic [63:0] l1d_addr_in,
    input logic [63:0] l1d_value_in,
    input logic [TAG_WIDTH-1:0] l1d_tag_in,
    input logic l1d_write_complete_in,

    // Processor Handshaking Outputs
    output logic proc_instr_ready_out,
    output logic proc_data_ready_out,

    // L1 Cache (L1D) Interface (outputs)
    output logic l1d_valid_out,
    output logic l1d_ready_out,
    output logic [63:0] l1d_addr_out,
    output logic [63:0] l1d_value_out,
    output logic l1d_we_out,
    output logic [TAG_WIDTH-1:0] l1d_tag_out,

    // Completion Interface Outputs
    output logic completion_valid_out,
    output logic [63:0] completion_value_out,
    output logic [TAG_WIDTH-1:0] completion_tag_out
  );

  module l1_data_cache #(
    parameter int A = 3,
    parameter int B = 64,
    parameter int C = 1536,
    parameter int PADDR_BITS = 22,
    parameter int MSHR_COUNT = 4,
    parameter int TAG_BITS = 10
  ) (
    // Inputs from LSU
    input logic clk_in,
    input logic rst_N_in,
    input logic cs_N_in,
    input logic flush_in,
    input logic lsu_valid_in,
    input logic lsu_ready_in,
    input logic [63:0] lsu_addr_in,
    input logic [63:0] lsu_value_in,
    input logic [TAG_BITS-1:0] lsu_tag_in,
    input logic lsu_we_in,
    // signals that go to LSU
    output logic lsu_valid_out,
    output logic lsu_ready_out,
    output logic [63:0] lsu_addr_out,
    output logic [63:0] lsu_value_out,
    output logic lsu_write_complete_out,
    output logic [TAG_BITS-1:0] lsu_tag_out,
    // Inputs from LLC
    input logic lc_ready_in,
    input logic lc_valid_in,
    input logic [PADDR_BITS-1:0] lc_addr_in,
    input logic [8*B-1:0] lc_value_in,
    // signals that go to LLC
    output logic lc_valid_out,
    output logic lc_ready_out,
    output logic [PADDR_BITS-1:0] lc_addr_out,
    output logic [8*B-1:0] lc_value_out,
    output logic lc_we_out
  );
endmodule
