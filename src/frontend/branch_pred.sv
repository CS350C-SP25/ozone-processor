import uop_pkg::*;
import op_pkg::*;

module branch_pred #(
    parameter CACHE_LINE_WIDTH = 64,
    parameter INSTRUCTION_WIDTH = op_pkg::INSTRUCTION_WIDTH,
    parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH
) (
    //TODO also include inputs for GHR updates.
    input clk_in,
    input rst_N_in,
    input logic[63:0] current_pc,
    input logic pc_valid,
    input logic l1i_valid,
    input logic l1i_ready,
    input logic [CACHE_LINE_WIDTH-1:0][7:0] l1i_cacheline,
    output logic[63:0] pred_pc, //goes into the program counter
    output uop_branch [SUPER_SCALAR_WIDTH-1:0] decode_branch_data, //goes straight into decode. what the branches are and if the super scalar needs to be squashed
    output logic[$clog2(SUPER_SCALAR_WIDTH+1)-1:0] pc_valid_out, //vaild out is saying ready for next as well
    output logic bp_l1i_valid_out,
    output logic[63:0] l1i_addr_out
);

    function  automatic logic[INSTRUCTION_WIDTH-1:0] get_instr_bits(
        input logic [CACHE_LINE_WIDTH-1:0][7:0] cacheline,
        input logic [63:0] starting_addr,
        input int instr_idx
    );
        return cacheline[l1i_addr_awaiting[5:0]+(instr_idx<<2)+3:l1i_addr_awaiting[5:0]+(instr_idx<<2)];
    endfunction

    logic[$clog2(SUPER_SCALAR_WIDTH+1)-1:0] pc_valid_out_next;

    always_ff @(posedge clk_in) begin
    end

    logic bp_l1i_valid_out_next;
    logic [63:0] l1i_addr_out_next;
    logic [63:0] l1i_addr_waiting; //address we are waiting on from cache
    logic done;
    always_comb begin
        if (pc_valid) begin // we have gotten a valid pc from the pc, lets fetch the instruction bits from the l1i. TODO only do this on flush otherwise it should come from the output of pred_pc on this cycle
            // i think the if statement should be if branch prediction correction || initial startup
            l1i_addr_out_next = current_pc;
            bp_l1i_valid_out_next = 1'b1;
        end else begin
            int valid_instructions = 0;
            if (l1i_valid) begin // we got the instruction bits back. predecode, update ras, pred_pc, look up ghr, etc
                done = 1'b0;
                for (int instr_idx = 0; instr_idx < SUPER_SCALAR_WIDTH; instr_idx++) begin
                    if (l1i_addr_awaiting[5:0]+(instr_idx<<2) <= CACHE_LINE_WIDTH - INSTRUCTION_WIDTH && !done) begin
                        if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:21] == 11'b11010110010) begin //RET
                            // pop off RAS, if RAS is empty, whatever X30 is if possible?
                            // set branch data for this index
                            // set the next l1i target to the predicted PC
                            done = 1;
                        end else if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:26] == 6'b000101) begin //B
                            // store branching info, ignore the remaining
                            // decode the predicted PC and do the add
                            // set branch data for this index
                            // set the next l1i target to the predicted PC
                            done = 1;
                        end else if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:26] == 6'b000101) begin // BL (same as B but we need to push to RAS)
                            pc_valid_out_next = instr_idx + 1;
                            // decode the predicted PC and do the add
                            // set branch data for this index
                            // push to RAS l1i_addr_awaiting[5:0]+(instr_idx<<2) + 4
                            // set the next l1i target to the predicted PC
                            done = 1;
                        end else if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:24] == 8'b01010100) begin
                            // done = branch_taken;
                        end
                    end
                end
                if (!done) begin
                    // two cases: cut short by cacheline alignment OR full super scalar. set pred PC accordingly and ensure l1i is ready
                end
            end else begin
            end
        end

        // this spot for ghr updates 
    end
endmodule