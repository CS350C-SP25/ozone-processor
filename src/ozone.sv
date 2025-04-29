`include "./backend/backend.sv"
`include "./frontend/frontend.sv"
`include "../mem/src/load_store_unit.sv"
`include "../mem/src/l1_data_cache.sv"
`include "./util/instr-queue.sv"

module ozone (
    input logic clk_in,
    input logic rst_N_in,
    input logic cs_N_in,
    input logic start,
    input logic [63:0] start_pc,
    input logic l1i_lc_ready_in,
    input logic l1i_lc_valid_in,
    input logic [63:0] l1i_lc_addr_in,
    input logic [511:0] l1i_lc_value_in,
    input logic l1d_lc_ready_in,
    input logic l1d_lc_valid_in,
    input logic [63:0] l1d_lc_addr_in,
    input logic [511:0] l1d_lc_value_in
);
  // --- Internal Wires ---
  logic bcond_resolved_out;
  logic pc_incorrect_out;
  logic taken_out;
  logic [63:0] pc_out;
  logic [18:0] correction_offset_out;
  logic exec_ready;

  instr_queue_t instruction_queue_in;
  instr_queue_t instruction_queue_out;

  // --- Wires between backend <-> LSU ---
  logic [63:0] backend_mem_addr_out;
  logic [$clog2(mem_pkg::LQ_SIZE)-1:0] backend_mem_tag_out;
  logic backend_mem_valid_out;
  logic [63:0] backend_mem_data_in;
  logic [$clog2(mem_pkg::LQ_SIZE)-1:0] backend_mem_resp_tag;
  logic backend_mem_valid_in;

  // --- Wires between LSU <-> L1D ---
  logic lsu_l1d_valid_out;
  logic lsu_l1d_ready_out;
  logic [63:0] lsu_l1d_addr_out;
  logic [63:0] lsu_l1d_value_out;
  logic lsu_l1d_we_out;
  logic [9:0] lsu_l1d_tag_out;

  logic l1d_lsu_valid_out;
  logic l1d_lsu_ready_out;
  logic [63:0] l1d_lsu_addr_out;
  logic [63:0] l1d_lsu_value_out;
  logic l1d_lsu_write_complete_out;
  logic [9:0] l1d_lsu_tag_out;

  // --- Wires between LSU -> Backend (completion) ---
  logic completion_valid_out;
  logic [63:0] completion_value_out;
  logic [9:0] completion_tag_out;

  // --- Frontend ---
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
      .lc_ready_in(l1i_lc_ready_in),
      .lc_valid_in(l1i_lc_valid_in),
      .lc_addr_in(l1i_lc_addr_in),
      .lc_value_in(l1i_lc_value_in),
      .exe_ready(exec_ready),
      .lc_valid_out(),
      .lc_ready_out(),
      .lc_addr_out(),
      .lc_value_out(),
      .lc_we_out(),
      .instruction_queue_in(instruction_queue_in)
  );
  
  logic q_full, q_empty;
  logic [$clog2(uop_pkg::INSTR_Q_DEPTH)-1:0] q_size;
  instruction_queue u_instruction_queue (
    .clk_in      (clk_in),
    .rst_N_in    (rst_N_in),
    // resets the q completely, empty, 0 size, etc.
    .flush_in    (pc_incorrect_out),
    // same function as reset
    // fix: pass a scalar element instead of the entire array
    .q_in        (instruction_queue_in),
    // fix: pack constant into an array to match port
    .enq_in      ({uop_pkg::INSTR_Q_WIDTH}),
    .deq_in      ({uop_pkg::INSTR_Q_WIDTH}),

    // fix: pass a scalar element from the output array
    .q_out       (instruction_queue_out),
    // the top width elements of the queue
    .full        (q_full),
    // 1 if the queue is full
    .empty       (q_empty),
    // 1 if the queue is empty
    // the #elems in the queue
    .size        (q_size)
);

  // --- Backend ---
  backend be (
      .clk_in(clk_in),
      .rst_N_in(rst_N_in),
      .instr_queue(instruction_queue_out),
      .q_valid(!q_full && !q_empty && q_size > uop_pkg::INSTR_Q_WIDTH),
      .q_increment_ready(q_increment_ready),

      // Mem interface
      .mem_data_in (completion_value_out),
      .mem_resp_tag(completion_tag_out),
      .mem_valid_in(completion_valid_out),

      .bcond_resolved_out(bcond_resolved_out),
      .pc_incorrect_out(pc_incorrect_out),
      .taken_out(taken_out),
      .pc_out(pc_out),
      .correction_offset_out(correction_offset_out),
      .ready_out(exec_ready),

      .mem_addr_out (backend_mem_addr_out),
      .mem_tag_out  (backend_mem_tag_out),
      .mem_valid_out(backend_mem_valid_out)
  );

  // --- Load Store Unit ---
  load_store_unit #(
      .QUEUE_DEPTH(8),
      .TAG_WIDTH  (10)
  ) lsu (
      .clk_in  (clk_in),
      .rst_N_in(rst_N_in),
      .cs_N_in (cs_N_in),

      // Processor Instruction Interface
      .proc_instr_valid_in(backend_mem_valid_out),
      .proc_instr_tag_in(backend_mem_tag_out),
      .proc_instr_is_write_in('0), // Assuming backend only issues reads for now, you can wire correctly

      // Processor Data Interface
      .proc_data_valid_in(backend_mem_valid_out),
      .proc_data_tag_in(backend_mem_tag_out),
      .proc_addr_in(backend_mem_addr_out),
      .proc_value_in('0),  // No store data for now unless backend supplies it

      // L1 Cache (L1D) Interface Inputs
      .l1d_valid_in(l1d_lsu_valid_out),
      .l1d_ready_in(l1d_lsu_ready_out),
      .l1d_addr_in(l1d_lsu_addr_out),
      .l1d_value_in(l1d_lsu_value_out),
      .l1d_tag_in(l1d_lsu_tag_out),
      .l1d_write_complete_in(l1d_lsu_write_complete_out),

      // Handshaking Outputs
      .proc_instr_ready_out(),  // not used
      .proc_data_ready_out (),  // not used

      // L1 Cache (L1D) Interface Outputs
      .l1d_valid_out(lsu_l1d_valid_out),
      .l1d_ready_out(lsu_l1d_ready_out),
      .l1d_addr_out(lsu_l1d_addr_out),
      .l1d_value_out(lsu_l1d_value_out),
      .l1d_we_out(lsu_l1d_we_out),
      .l1d_tag_out(lsu_l1d_tag_out),

      // Completion Outputs
      .completion_valid_out(completion_valid_out),
      .completion_value_out(completion_value_out),
      .completion_tag_out  (completion_tag_out)
  );

  // --- L1 Data Cache ---
  l1_data_cache #(
      .A(3),
      .B(64),
      .C(1536),
      .PADDR_BITS(22),
      .MSHR_COUNT(4),
      .TAG_BITS(10)
  ) l1d (
      .clk_in(clk_in),
      .rst_N_in(rst_N_in),
      .cs_N_in(cs_N_in),
      .flush_in('0),  // no flush
      .lsu_valid_in(lsu_l1d_valid_out),
      .lsu_ready_in(lsu_l1d_ready_out),
      .lsu_addr_in(lsu_l1d_addr_out),
      .lsu_value_in(lsu_l1d_value_out),
      .lsu_tag_in(lsu_l1d_tag_out),
      .lsu_we_in(lsu_l1d_we_out),

      .lsu_valid_out(l1d_lsu_valid_out),
      .lsu_ready_out(l1d_lsu_ready_out),
      .lsu_addr_out(l1d_lsu_addr_out),
      .lsu_value_out(l1d_lsu_value_out),
      .lsu_write_complete_out(l1d_lsu_write_complete_out),
      .lsu_tag_out(l1d_lsu_tag_out),

      .lc_ready_in(l1d_lc_ready_in),
      .lc_valid_in(l1d_lc_valid_in),
      .lc_addr_in (l1d_lc_addr_in[21:0]),  // truncating to match 22 bits
      .lc_value_in(l1d_lc_value_in),

      .lc_valid_out(),
      .lc_ready_out(),
      .lc_addr_out(),
      .lc_value_out(),
      .lc_we_out()
  );

endmodule
