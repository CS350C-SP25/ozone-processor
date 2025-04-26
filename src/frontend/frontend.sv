`include "../util/stack.sv"
`include "./branch_pred.sv"
`include "./cache/l1_instr_cache.sv"
import op_pkg::*;
import uop_pkg::*;


// top level module of the frontend, communicates with backend's top level module through instruction queue
module frontend #(
    parameter INSTRUCTION_WIDTH = op_pkg::INSTRUCTION_WIDTH,
    parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH,
    parameter CACHE_LINE_WIDTH = 64
) (
    input logic clk_in,
    input logic rst_N_in,
    input logic cs_N_in,
    input logic start,
    input logic [63:0] start_pc,
    input logic x_bcond_resolved,
    input logic x_pc_incorrect,
    input logic x_taken,
    input logic [63:0] x_pc,
    input logic [18:0] x_correction_offset,
    input logic lc_ready_in,
    input logic lc_valid_in,
    input logic [63:0] lc_addr_in,
    input logic [511:0] lc_value_in,
    input logic exe_ready,
    output logic lc_valid_out,
    output logic lc_ready_out,
    output logic [63:0] lc_addr_out,
    output logic [511:0] lc_value_out,
    output logic lc_we_out,
    output uop_insn instruction_queue_in [INSTR_Q_WIDTH-1:0] 
);
    logic l1i_valid;
    logic l1i_ready;
    logic [7:0] l1i_cacheline[CACHE_LINE_WIDTH-1:0];
    logic [63:0] pred_pc;
    uop_branch decode_branch_data [SUPER_SCALAR_WIDTH-1:0];
    logic pc_valid_out;
    logic bp_l1i_valid_out;
    logic [63:0] l1i_addr_out;
    logic [7:0] l0_cacheline [CACHE_LINE_WIDTH-1:0];
    logic [INSTRUCTION_WIDTH-1:0] fetched_ops [SUPER_SCALAR_WIDTH-1:0];
    logic fetch_valid;
    logic fetch_ready;
    logic bp_l0_valid;
    logic [63:0] fetch_pc;
    logic decode_ready;

    branch_pred #(
        .CACHE_LINE_WIDTH(64),
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH),
        .SUPER_SCALAR_WIDTH(SUPER_SCALAR_WIDTH),
        .IST_ENTRIES(1024),
        .BTB_ENTRIES(128),
        .GHR_K(8),
        .PHT_N(8),
        .L0_WAYS(8)
    ) bp (
        .clk_in(clk_in),
        .rst_N_in(rst_N_in),
        .l1i_valid(l1i_valid),
        .l1i_ready(l1i_ready),
        .x_bcond_resolved(x_bcond_resolved),
        .x_pc_incorrect(x_pc_incorrect),  // this means that the PC that we had originally predicted was incorrect. We need to fix.
        .x_taken(x_taken),  // if the branch resolved as taken or not -- to update PHT and GHR
        .x_pc(x_pc), // pc that is currently in the exec phase (the one that just was resolved)
        .x_correction_offset(x_correction_offset), // the offset of the correction from x_pc (could change this to be just the actual correct PC instead ??)
        .l1i_cacheline(l1i_cacheline),
        .pred_pc(pred_pc),  //goes into the fetch
        .decode_branch_data(decode_branch_data), //goes straight into decode. what the branches are and if the super scalar needs to be squashed
        .pc_valid_out(pc_valid_out),  // sending a predicted instruction address. 
        .bp_l1i_valid_out(bp_l1i_valid_out), //fetch uses this + pc valid out to determine if waiting for l1i or 
        .bp_l0_valid(bp_l0_valid),
        .l1i_addr_out(l1i_addr_out),
        .l0_cacheline(l0_cacheline) // this gets fed to fetch
    );

    l1_instr_cache #(
        // parameter int A = 3,
        // parameter int B = 64,
        // parameter int C = 1536,
        // parameter int PADDR_BITS = 22,
        // parameter int MSHR_COUNT = 4,
        // parameter int TAG_BITS = 10
    ) l1i (
        // Inputs from LSU
        .clk_in(clk_in),
        .rst_N_in(rst_N_in),
        .cs_N_in(cs_N_in),
        .flush_in(x_pc_incorrect),
        .l0_ready_in(1'b1),
        .l0_addr_in(l1i_addr_out),
        // signals that go to l0
        .l0_valid_out(l1i_valid),
        .l0_ready_out(l1i_ready),
        .l0_addr_out(l1i_addr_out),
        .l0_value_out(l1i_cacheline), //TODO change this to be the l1i cacheline 
        // Inputs from LLC - in this case, we are just doing DIMM (?)
        .lc_ready_in(lc_ready_in), 
        .lc_valid_in(lc_valid_in),
        .lc_addr_in(lc_addr_in),
        .lc_value_in(lc_value_in),
        // signals that go to LLC - in this case, we are just doing DIMM (?)
        .lc_valid_out(lc_valid_out),
        .lc_ready_out(lc_ready_out),
        .lc_addr_out(lc_addr_out),
        .lc_value_out(lc_value_out),
        .lc_we_out(lc_we_out)
    );

    fetch #(
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH),
        .SUPER_SCALAR_WIDTH(SUPER_SCALAR_WIDTH),
        .CACHE_LINE_WIDTH(64)
    ) fetch_stage (
        .clk_in(clk_in),                                      // clock signal
        .rst_N_in(rst_N_in),                                    // reset signal, active low       
        .flush_in(x_pc_incorrect),                                    // signal for misprediction                          
        .l0_cacheline(l0_cacheline),   // cacheline sent from l0
        .l1i_cacheline(l1i_cacheline),   // cacheline sent from l0
        .bp_l0_valid(pc_valid_out & ~bp_l1i_valid_out),                                 // branch prediction's cacheline is valid
        .l1i_valid(l1i_valid),
        .pc_valid(pc_valid_out),  // all pcs valid
        .pred_pc(pred_pc),                              // predicted pc
        .fetched_instrs(fetched_ops), // instrns to send to decode
        .fetch_valid(fetch_valid),                                // valid when done (sent to decode)
        .fetch_ready(fetch_ready),                                // fetch is ready to receive cacheline (sent to bp)
        .next_pc(fetch_pc)                              // next PC, predicted from bp to decode
    );

    decode #(
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH),
        .SUPER_SCALAR_WIDTH(SUPER_SCALAR_WIDTH),
        .INSTR_Q_DEPTH(INSTR_Q_DEPTH),
        .INSTR_Q_WIDTH(INSTR_Q_WIDTH)
    ) decode_stage (
        .clk_in(clk_in),
        .rst_N_in(rst_N_in),
        .flush_in(x_pc_incorrect),
        .fetched_ops(fetched_ops),
        .branch_data(decode_branch_data),
        .pc(fetch_pc),
        .fetch_valid(fetch_valid),
        .exe_ready(exe_ready),
        .decode_ready(decode_ready),
        .instruction_queue_in(instruction_queue_in)
    );
endmodule
