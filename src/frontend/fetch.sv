import uop_pkg::*;
import op_pkg::*;

// fetch logic unit frfr
// we will generate multiple of these in our top level module to simulate the multiple instn fetch
// one module of this will only fetch one instruction at a time
module fetch #(
    parameter INSTRUCTION_WIDTH = op_pkg::INSTRUCTION_WIDTH,
    parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH,
    parameter CACHE_LINE_WIDTH = 64, // TODO: waiting for the l1 i$ to be added to change this
) (
    input logic clk_in,                                      // clock signal
    input logic rst_N_in,                                    // reset signal, active low I assume?
    input logic l1i_valid,
    input logic l1i_ready,
    input logic [7:0] l1i_cacheline [CACHE_LINE_WIDTH-1:0],  // cacheline sent from icache
    input logic bp_l1i_valid_in,
    input logic[$clog2(SUPER_SCALAR_WIDTH+1)-1:0] pc_valid_in, // vector for all the pc's being valid???
    input logic[63:0] l1i_addr_out,
    output logic [INSTRUCTION_WIDTH-1:0] fetched_cacheline [SUPER_SCALAR_WIDTH-1:0],
    output logic fetch_valid,                                // valid when done
    output logic [63:0] next_pc                             // next PC, predicted from BTB to decode
);

logic [63:0] last_pc;
int last_instr_block;

// req to icache when we receive a valid pc
// update the pc through the btb/ist
always_comb begin: fetch_comb_logic
    if (l1i_valid) begin
        // aligning cacheline fetched to desired super scalar width
        // assuming that total size of instructions fetched at once for super scalar < CACHE_LINE_WIDTH
        for (int i = 0; i < SUPER_SCALAR_WIDTH; i++) begin
            if (last_instr_block == 16) begin
                // consecutive instructions are spanning two diff cachelines
                // need to stall for next cacheline ?? is this how you stall idk lol
                last_instr_block = '0;
            end else begin
                for (int j = 0; j < INSTRUCTION_WIDTH; j = j + 8) begin // 1 byte at a time
                    fetched_cacheline [i] = l1i_cacheline [last_instr_block * 4:(last_instr_block * 4) + 4];
                    last_instr_block = last_instr_block + 1;
                end
            end
        end
        fetch_valid = 1;
    end else begin
        // stall waiting for l1i cacheline given to be valid
    end
    if (bp_l1i_valid_in && pc_valid_in) begin
        last_pc = l1i_addr_out;
    end
end

// keep da pipeline pipelining
always_ff@(posedge clk_in) begin
    if (rst_N_in) begin
        next_pc <= last_pc;
    end else begin
        fetch_valid <= '0;
        last_instr_block <= '0;
    end
end


endmodule