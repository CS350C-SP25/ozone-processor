import uop_pkg::*;
import op_pkg::*;

module branch_pred #(
    parameter CACHE_LINE_WIDTH = 64,
    parameter INSTRUCTION_WIDTH = op_pkg::INSTRUCTION_WIDTH,
    parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH
    parameter IST_ENTRIES = 1024,
    parameter BTB_ENTRIES = 128
) (
    //TODO also include inputs for GHR updates.
    input clk_in,
    input rst_N_in,
    input logic l1i_valid,
    input logic l1i_ready,
    input logic pc_correction,
    input logic [63:0] correct_pc,
    input logic [7:0] l1i_cacheline [CACHE_LINE_WIDTH-1:0],
    output logic[63:0] pred_pc, //goes into the program counter
    output uop_branch [SUPER_SCALAR_WIDTH-1:0] decode_branch_data, //goes straight into decode. what the branches are and if the super scalar needs to be squashed
    output logic[$clog2(SUPER_SCALAR_WIDTH+1)-1:0] pc_valid_out, // sending a predicted instruction address.
    output logic bp_l1i_valid_out,
    output logic[63:0] l1i_addr_out
);

    //FSM control
    logic [63:0] current_pc; // pc register
    logic [63:0] l1i_addr_awaiting; //address we are waiting on from cache; register
    logic bp_l1i_valid_out_next; //wire
    uop_branch [SUPER_SCALAR_WIDTH-1:0] branch_data_next;

    // RAS
    logic ras_push;
    logic ras_push_next;
    logic ras_pop;
    logic ras_pop_next;
    logic[63:0] ras_next_push;
    logic[63:0] ras_next_push_next;
    logic[63:0] ras_top;
    logic ras_restoreTail; //ignore tail resets for now (this can be part of misprediction correction for a mildly better RAS acc)
    logic[$clog2(8)-1:0] ras_newTail;
    stack #(.STACK_DEPTH(8), .ENTRY_SIZE(64)) ras (
        .clk_in(clk_in),
        .rst_N_in(rst_N_in),
        .push(ras_push),
        .pop(ras_pop),
        .pushee(ras_next_push),
        .restoreTail(ras_restoreTail),
        .newTail(ras_newTail),
        .stack_out(ras_top)
    );


    function  automatic logic[INSTRUCTION_WIDTH-1:0] get_instr_bits(
        input logic [CACHE_LINE_WIDTH-1:0][7:0] cacheline,
        input logic [63:0] starting_addr,
        input int instr_idx
    );
        return cacheline[starting_addr[5:0]+(instr_idx<<2)+3:starting_addr[5:0]+(instr_idx<<2)];
    endfunction

    function automatic void pred_bcond (
        input logic [63:0] pc,
        output logic branch_taken,
        output logic pred_pc
    );
    endfunction

    always_ff @(posedge clk_in) begin
        if (rst_N_in) begin
            current_pc <= l1i_addr_out_next;
            l1i_addr_awaiting <= l1i_addr_out_next; //uh we could prob turn this all into cur pc but im not sure if theyll diverge
            pred_pc <= l1i_addr_out_next; // "
            decode_branch_data <= branch_data_next;
        end else begin
            current_pc <= '0;
            l1i_addr_awaiting <= '0;
            pred_pc <= '0;
            decode_branch_data <= '0;
            pc_valid_out <= '0;
            bp_l1i_valid_out <= '0;
            l1i_addr_out <= '0;
        end
    end

    always_comb begin
        if (pc_correction) begin // we have gotten a valid pc from the pc, lets fetch the instruction bits from the l1i. TODO only do this on flush otherwise it should come from the output of pred_pc on this cycle
            // i think the if statement should be if branch prediction correction || initial startup
            // TODO stall if we have instruction inflight from l1ic
            l1i_addr_out_next = current_pc;
            bp_l1i_valid_out_next = 1'b1;
        end else begin
            if (l1i_valid) begin // we got the instruction bits back. predecode, update ras, pred_pc, look up ghr, etc
                done = 1'b0;
                for (int instr_idx = 0; instr_idx < SUPER_SCALAR_WIDTH; instr_idx++) begin
                    if (l1i_addr_awaiting[5:0]+(instr_idx<<2) <= CACHE_LINE_WIDTH - INSTRUCTION_WIDTH && !done) begin
                        if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:21] == 11'b11010110010) begin //RET
                            // pop off RAS, if RAS is empty, sucks to be us. 
                            branch_data_next[instr_idx].branch_target = ras_top;
                            //these 2 fields are the register put together (its a union but quartus doesnt support unions)
                            branch_data_next[instr_idx].condition = get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[4:1];
                            branch_data_next[instr_idx].predict_taken = get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[0];
                            pc_valid_out_next = instr_idx + 1; //this is the last relevant address we have branched away from this cacheline (prob)
                            l1i_addr_out_next = ras_top; //fetch the next address
                            ras_pop_next = 1'b1;
                            done = 1;
                        end else if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:26] == 6'b000101) begin //B
                            // decode the predicted PC and do the add
                            // store branching info, ignore the remaining
                            // set branch data for this index
                            branch_data_next[instr_idx].branch_target = pc + {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25]}}, get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25:0]} + (instr_idx << 2);
                            pc_valid_out_next = instr_idx + 1; //this is the last relevant address we have branched away from this cacheline (prob)
                            // set the next l1i target to the predicted PC
                            l1i_addr_out_next = pc + {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25]}}, get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25:0]} + (instr_idx << 2);
                            done = 1;
                        end else if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:26] == 6'b100101) begin // BL (same as B but we need to push to RAS)
                            // push to RAS l1i_addr_awaiting[5:0]+(instr_idx<<2) + 4
                            ras_push_next = 1'b1;
                            ras_next_push_next = l1i_addr_awaiting[5:0]+(instr_idx<<2) + 4; // return address
                            // decode the predicted PC and do the add
                            // store branching info, ignore the remaining
                            // set branch data for this index
                            branch_data_next[instr_idx].branch_target = pc + {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25]}}, get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25:0]} + (instr_idx << 2);
                            pc_valid_out_next = instr_idx + 1; //this is the last relevant address we have branched away from this cacheline (prob)
                            // set the next l1i target to the predicted PC
                            l1i_addr_out_next = pc + {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25]}}, get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25:0]} + (instr_idx << 2);
                            done = 1;
                        end else if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:24] == 8'b01010100) begin
                            // done = branch_taken;
                            // for now lets just always assume branch not taken we can adjust this later with a GHR and PHT
                            branch_data_next[instr_idx].branch_target = pc + {{45{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[23]}}, get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[23:5]} + (instr_idx << 2);
                            branch_data_next[instr_idx].condition = get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[3:0];
                            branch_data_next[instr_idx].predict_taken = 1'b0;
                        end 
                    end
                end
                if (!done) begin
                    // two cases: cut short by cacheline alignment OR full super scalar. set pred PC accordingly and ensure l1i is ready
                    pc_valid_out_next = l1i_addr_awaiting[5:0] <= 64 - (SUPER_SCALAR_WIDTH << 2) ? SUPER_SCALAR_WIDTH : (64 - l1i_addr_awaiting[5:0]) >> 2;
                    l1i_addr_out_next = l1i_addr_awaiting + (pc_valid_out_next << 2);
                end
                bp_l1i_valid_out_next = 1'b1;
            end else begin
                //l1i was not valid, we will stall until it is valid
                // default values are set at the top of the always comb block.
            end
        end
    end
endmodule
