`include "../../util/uop_pkg.sv"
`include "../reg_pkg.sv"
`include "../rob_pkg.sv"
`include "../is_pkg.sv"
`include "../../fpu/fpmult.sv"
`include "../../fpu/fpadder.sv"

import uop_pkg::*;
import reg_pkg::*;
import is_pkg::*;
import rob_pkg::*;

module lsu_ins_decoder #(
    parameter LQ_SIZE = 8
) (
    input  logic clk_in,
    input  logic rst_N_in,
    input  logic flush_in,

    // From ROB
    input  rob_issue insn_in,

    // D-cache response
    input  logic [reg_pkg::WORD_SIZE-1:0] mem_data_in,
    input  logic [$clog2(LQ_SIZE)-1:0] mem_resp_tag,
    input  logic mem_valid_in,

    // Memory request output
    output logic [reg_pkg::WORD_SIZE-1:0] mem_addr_out,
    output logic [$clog2(LQ_SIZE)-1:0] mem_tag_out,
    output logic mem_valid_out,

    // Regfile
    output RegFileWritePort reg_pkt_out,

    // Notify ROB this unit can take a new instruction
    output logic ready_out
);

    typedef struct packed {
        logic valid;
        logic [reg_pkg::WORD_SIZE-1:0] addr;
        logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] phys_dest;
    } lq_entry_t;

    lq_entry_t load_queue[LQ_SIZE];
    logic [$clog2(LQ_SIZE)-1:0] alloc_ptr;
    logic [$clog2(LQ_SIZE)-1:0] commit_ptr;

    // Ready if queue has free slot
    assign ready_out = !load_queue[alloc_ptr].valid;

    // Dispatch a new load
    always_ff @(posedge clk_in or negedge rst_N_in) begin
        if (!rst_N_in || flush_in) begin
            for (int i = 0; i < LQ_SIZE; i++) begin
                load_queue[i].valid <= 0;
            end
            alloc_ptr <= 0;
        end else begin
            // Clear load entry upon completion
            if (mem_valid_in) begin
                load_queue[mem_resp_tag].valid <= 0;
            end
            if (insn_in.valid && insn_in.uop.uopcode == UOP_LOAD && ready_out) begin
                load_queue[alloc_ptr].valid     <= 1;
                load_queue[alloc_ptr].addr      <= insn_in.r1_val + insn_in.r2_val;
                load_queue[alloc_ptr].phys_dest <= insn_in.dest_reg_phys;
                mem_addr_out                    <= insn_in.r1_val + insn_in.r2_val;
                mem_tag_out                     <= alloc_ptr;
                mem_valid_out                   <= 1;
                alloc_ptr                       <= (alloc_ptr + 1) % LQ_SIZE;
            end else begin
                mem_valid_out <= 0;
            end
        end
    end

    // Handle memory response
    always_comb begin
        reg_pkt_out = '0;
        if (mem_valid_in && load_queue[mem_resp_tag].valid) begin
            reg_pkt_out.index_in = load_queue[mem_resp_tag].phys_dest;
            reg_pkt_out.data_in  = mem_data_in;
            reg_pkt_out.en       = 1;
        end
    end

endmodule