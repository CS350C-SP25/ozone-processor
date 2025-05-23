`ifndef FETCH
`define FETCH 

`include "../util/uop_pkg.sv"
`include "../util/op_pkg.sv"

import uop_pkg::*;
import op_pkg::*;


// fetch logic unit.
// will choose from the cacheline received from branch predictor and the pc which instructions
// to send over to decode at most in super_scalar_width.
module fetch #(
    parameter INSTRUCTION_WIDTH  = op_pkg::INSTRUCTION_WIDTH,
    parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH,
    parameter CACHE_LINE_WIDTH   = 64
) (
    input logic clk_in,  // clock signal
    input logic rst_N_in,  // reset signal, active low       
    input logic flush_in,  // signal for misprediction                          
    input logic [CACHE_LINE_WIDTH*8-1:0] l0_cacheline,  // cacheline sent from l0
    input logic [CACHE_LINE_WIDTH*8-1:0] l1i_cacheline,  // cacheline sent from l0
    input logic bp_l0_valid,  // branch prediction's cacheline is valid
    input logic l1i_valid,
    input logic pc_valid,  // all pcs valid
    input logic [63:0] pred_pc,  // predicted pc
    input logic decode_ready,  // when decode is ready
    output instruction_array fetched_instrs,  // instrns to send to decode
    output logic fetch_valid,  // valid when done (sent to decode)
    output logic fetch_ready,  // fetch is ready to receive cacheline (sent to bp)
    output logic [63:0] next_pc  // next PC, predicted from bp to decode
);

  localparam int BLOCK_OFFSET_BITS = $clog2(CACHE_LINE_WIDTH);
  logic                    buffer_done;
  logic                    l1i_waiting;
  logic                    l1i_waiting_next;
  logic                    fetch_valid_next;
  logic                    discard_l1i;
  logic                    discard_l1i_next;

  instruction_array        l1i_fetched_instrs;
  instruction_array        l0_fetched_instrs;


  logic                    ready_next;  // 1-bit signal
  logic             [63:0] pc_next;  // 64-bit signal
  instruction_array        next_instrs;


  align_instructions #(
      .SUPER_SCALAR_WIDTH(SUPER_SCALAR_WIDTH),
      .CACHE_LINE_WIDTH  (CACHE_LINE_WIDTH),
      .INSTRUCTION_WIDTH (INSTRUCTION_WIDTH)
  ) l1i_align (
      .offset(pred_pc[5:0]),
      .cacheline(l1i_cacheline),
      .instr_out(l1i_fetched_instrs)
  );

  align_instructions #(
      .SUPER_SCALAR_WIDTH(SUPER_SCALAR_WIDTH),
      .CACHE_LINE_WIDTH  (CACHE_LINE_WIDTH),
      .INSTRUCTION_WIDTH (INSTRUCTION_WIDTH)
  ) l0_align (
      .offset(pred_pc[5:0]),
      .cacheline(l0_cacheline),
      .instr_out(l0_fetched_instrs)
  );


  // start copying over instructions when received a valid cacheline and pc
  // pass off the the next predicted pc to decode
  assign fetch_valid_next = ~flush_in & ((bp_l0_valid & pc_valid) | (l1i_valid & ~discard_l1i));
  assign discard_l1i_next = flush_in ? (l1i_waiting_next & ~l1i_valid) : (l1i_valid || (bp_l0_valid && pc_valid)) ? 1'b0 : discard_l1i;
  assign ready_next = decode_ready;  // decode accepted req from us, we can also move next
  // we got a new l1i request, we are waiting for an l1i request, the l1i request hasnt been resolved, the discard one needs to be handled first
  assign l1i_waiting_next = (((pc_valid & ~bp_l0_valid) | l1i_waiting) & ~l1i_valid) | discard_l1i;
  assign pc_next = pred_pc;

  assign next_instrs = flush_in ?
      '{default: 0}
      : (l1i_valid ?
         l1i_fetched_instrs : ((bp_l0_valid && pc_valid) ? l0_fetched_instrs : fetched_instrs));


  // ctrl signals to keep checking for on every posedge of the clock
  always_ff @(posedge clk_in) begin
    // if NOT resetting
    if (rst_N_in) begin
      // need to make sure that decode IS ready so we can update our outputs
      if (decode_ready) begin
        fetched_instrs <= next_instrs;
        fetch_valid <= fetch_valid_next;
        discard_l1i <= discard_l1i_next;
        fetch_ready <= ready_next;
        next_pc <= pc_next;
        l1i_waiting <= l1i_waiting_next;
      end
    end else begin
      fetched_instrs <= '{default: 0};
      fetch_valid <= '0;
      discard_l1i <= '0;
      fetch_ready <= '0;
      next_pc <= '0;
      l1i_waiting <= '0;
    end
  end

endmodule

module align_instructions #(
    parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH,
    parameter CACHE_LINE_WIDTH   = 64,
    parameter INSTRUCTION_WIDTH  = op_pkg::INSTRUCTION_WIDTH
) (
    input logic [$clog2(CACHE_LINE_WIDTH)-1:0] offset,
    input logic [CACHE_LINE_WIDTH*8-1:0] cacheline,
    output instruction_array instr_out
);
  genvar i;
  generate
    for (i = 0; i < SUPER_SCALAR_WIDTH; i++) begin : instr_extract
      // Compute the byte offset for the start of the instruction
      logic [$clog2(CACHE_LINE_WIDTH)-1:0] byte_start;
      assign byte_start = offset + (i * 4);
      assign instr_out[i] = (byte_start + 3 < CACHE_LINE_WIDTH) ? 
                {
                    cacheline[(byte_start + 3) * 8 +: 8], // MSB (byte 3)
          cacheline[(byte_start + 2) * 8 +: 8],
                    cacheline[(byte_start + 1) * 8 +: 8],
                    cacheline[(byte_start + 0) * 8 +: 8]  // LSB (byte 0)
          } : {8'hD5, 8'h03, 8'h20, 8'h1F};
    end
  endgenerate
endmodule

`endif
