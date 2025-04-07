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
    output logic pc_valid_out, // sending a predicted instruction address.
    output logic bp_l1i_valid_out,
    output logic[63:0] l1i_addr_out
);

    typedef enum logic [2:0] {
        IST_NON_BRANCH  = 3'b000,
        IST_B           = 3'b001,
        IST_BL          = 3'b010,
        IST_BCOND       = 3'b011,
        IST_RET         = 3'b100
    } ist_entry_t;

    // tables
    ist_entry_t istable [$clog2(IST_ENTRIES)-1:0];
    logic[25:0] btb [$clog2(BTB_ENTRIES)-1:0]; // stores B, BL, Bcond offsets; Bcond decisions stored elsewhere

    //FSM control
    logic [63:0] current_pc; // pc register
    logic instruction_bits_inflight; // do we need to wait for the L1i to resolve? register
    logic new_pc_predicted; //wire for the above
    logic [63:0] pred_pc; // wire
    logic [63:0] l1i_addr_waiting; //address we are waiting on from cache; register
    logic discard_inflight;
    logic discard_inflight_next;

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
        return cacheline[l1i_addr_awaiting[5:0]+(instr_idx<<2)+3:l1i_addr_awaiting[5:0]+(instr_idx<<2)];
    endfunction

    function automatic void pred_bcond (
        input logic [63:0] pc,
        output logic branch_taken,
        output logic pred_pc
    );
    endfunction
    
    function automatic void speculative_decode (
        input logic [63:0] pc,
        input logic [63:0] spec_ras_top,
        output logic [63:0] pred
    );
        // note that this function doesnt modify ras or ist, we will only do this after we get the instruction bits back and feel certain
        // if we have a BL followed by a ret in the next set of super scalar we need to use make sure ras top was set correctly for better prediction chances.
        logic found_branch;
        logic [63:0] res = pc;
        for (int instr_idx = 0; instr_idx < SUPER_SCALAR_WIDTH; instr_idx++) begin
            if (pc[5:0]+(instr_idx<<2) <= CACHE_LINE_WIDTH - INSTRUCTION_WIDTH && !found_branch) begin
                case (istable[pc[11:2] + instr_idx])
                    IST_NON_BRANCH:
                        res = res + 4;
                        break;
                    IST_B:
                        res = pc+(instr_idx<<2) + btb[pc[8:2]+instr_idx];
                        found_branch = 1'b1;
                        break;
                    IST_BL:
                        res = pc+(instr_idx<<2) + btb[pc[8:2]+instr_idx];
                        found_branch = 1'b1;
                        break;
                    IST_BCOND:
                        pred_bcond(pc+(instr_idx<<2), found_branch, res);
                        break;
                    IST_RET:
                        res = spec_ras_top;
                        found_branch;
                        break;
                    default:
                        $$display("bad ist entry");
                        break;
                endcase
            end
        end
        pred = res;
    endfunction


    function automatic void partial_predecode (
        input logic [63:0] pc,
        input logic [7:0] actual_cacheline [CACHE_LINE_WIDTH-1:0],
        output logic [63:0] actual_pc
    );
        logic found_branch;
        logic [63:0] res = pc;
        for (int instr_idx = 0; instr_idx < SUPER_SCALAR_WIDTH; instr_idx++) begin
            if (pc[5:0]+(instr_idx<<2) <= CACHE_LINE_WIDTH - INSTRUCTION_WIDTH && !found_branch) begin
                if (get_instr_bits(actual_cacheline, pc, instr_idx)[31:21] == 11'b11010110010) begin // RET case
                    res = ras_top;
                    found_branch = 1'b1;
                end else if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:26] == 6'b000101) begin // B
                    res = res + {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25]}}, get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25:0]};
                    found_branch = 1'b1;
                end else if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:26] == 6'b100101) begin // BL
                    res = res + {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25]}}, get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25:0]};
                    found_branch = 1'b1;
                end else if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:24] == 8'b01010100) begin //B cond
                end else begin
                end
            end
        end
        actual_pc = res;
    endfunction


    always_ff @(posedge clk_in) begin
        if (rst_N_in) begin
            instruction_bits_inflight <= new_pc_predicted | instruction_bits_inflight;
            l1i_addr_awaiting <= pred_pc;
            current_pc <= pred_pc;
            bp_l1i_valid_out <= new_pc_predicted;
            l1i_addr_out <= pred_pc;
            pc_valid_out <= new_pc_predicted;
            discard_inflight <= discard_inflight_next;
        end else begin
            instruction_bits_inflight <= 1'b0;
            current_pc <= '0;
            l1i_addr_awaiting <= '0;
            bp_l1i_valid_out <= 1'b0;
            l1i_addr_out <= '0;
            pc_valid_out <= 1'b0;
            discard_inflight = 1'b0;
        end
    end



    always_comb begin
        if (pc_correction) begin // we will start with PC correction = 1 this will also be set if we have a mispredict in the backend
            // if instruction bits are in flight pred pc = correction pc (we stall)
            if (instruction_bits_inflight && !l1i_valid) begin
                pred_pc = correct_pc;
                new_pc_predicted = 1'b0;
                discard_inflight_next = 1'b1;
            end else begin // spec decode correction pc
                speculative_decode(
                    .pc(correct_pc),
                    .spec_ras_top(ras_top),
                    .pred(pred_pc)
                );
                new_pc_predicted = 1'b1;
            end
        end else begin
            // we have the correct PC according to the execute stage
            // stall if instruction bits are in flight
            if (!l1i_valid) begin
                pred_pc = current_pc;
                new_pc_predicted = 1'b0;
                discard_inflight_next = discard_inflight;
            end else if (!discard_inflight) begin // instruction bits not in flight, verify that our spec decode was correct
                //actual PC = ...

                if (actual_pc == current_pc) begin
                    // if spec decode correct, pred PC based off current pc YIPPEE

                end else begin
                    //oops we decoded wrong. (programmers fault)
                    speculative_decode(
                        .pc(actual_pc),
                        .spec_ras_top(ras_top),
                        .pred(pred_pc)
                    );
                    new_pc_predicted = 1'b1;

                    // decode will need to handle itself. it has the same instruction bits as us at this point and will need to squash a bad spec decode for itself. maybe we can combine this check into 1 higher level comb module
                end
            end else begin
                // we discard the cacheline previously requested and start fresh with a speculative decode on the current PC.
                speculative_decode(
                    .pc(current_pc),
                    .spec_ras_top(ras_top),
                    .pred(pred_pc)
                );
                new_pc_predicted = 1'b1;
            end
        end
    end
endmodule


// if (pc_valid) begin // we have gotten a valid pc from the pc, lets fetch the instruction bits from the l1i. TODO only do this on flush otherwise it should come from the output of pred_pc on this cycle
//     // i think the if statement should be if branch prediction correction || initial startup
//     l1i_addr_out_next = current_pc;
//     bp_l1i_valid_out_next = 1'b1;
// end else begin
//     int valid_instructions = 0;
//     if (l1i_valid) begin // we got the instruction bits back. predecode, update ras, pred_pc, look up ghr, etc
//         done = 1'b0;
//         for (int instr_idx = 0; instr_idx < SUPER_SCALAR_WIDTH; instr_idx++) begin
//             if (l1i_addr_awaiting[5:0]+(instr_idx<<2) <= CACHE_LINE_WIDTH - INSTRUCTION_WIDTH && !done) begin
//                 if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:21] == 11'b11010110010) begin //RET
//                     // pop off RAS, if RAS is empty, sucks to be us. 
//                     branch_data[instr_idx].branch_target = ras_top;
//                     //these 2 fields are the register put together (its a union but quartus doesnt support unions)
//                     branch_data[instr_idx].condition = get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[4:1];
//                     branch_data[instr_idx].predict_taken = get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[0];
//                     pc_valid_out_next = instr_idx + 1; //this is the last relevant address we have branched away from this cacheline (prob)
//                     l1i_addr_out_next = ras_top; //fetch the next address
//                     bp_l1i_valid_out_next = 1'b1;
//                     ras_pop_next = 1'b1;
//                     done = 1;
//                 end else if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:26] == 6'b000101) begin //B
//                     // decode the predicted PC and do the add
//                     // store branching info, ignore the remaining
//                     // set branch data for this index
//                     branch_data[instr_idx].branch_target = pc + {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25]}}, get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25:0]};
//                     pc_valid_out_next = instr_idx + 1; //this is the last relevant address we have branched away from this cacheline (prob)
//                     // set the next l1i target to the predicted PC
//                     l1i_addr_out_next = pc + {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25]}}, get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25:0]};
//                     bp_l1i_valid_out_next = 1'b1;
//                     done = 1;
//                 end else if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:26] == 6'b100101) begin // BL (same as B but we need to push to RAS)
//                     pc_valid_out_next = instr_idx + 1;
//                     // push to RAS l1i_addr_awaiting[5:0]+(instr_idx<<2) + 4
//                     ras_push_next = 1'b1;
//                     ras_next_push_next = l1i_addr_awaiting[5:0]+(instr_idx<<2) + 4; // return address
//                     // decode the predicted PC and do the add
//                     // store branching info, ignore the remaining
//                     // set branch data for this index
//                     branch_data[instr_idx].branch_target = pc + {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25]}}, get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25:0]};
//                     pc_valid_out_next = instr_idx + 1; //this is the last relevant address we have branched away from this cacheline (prob)
//                     // set the next l1i target to the predicted PC
//                     l1i_addr_out_next = pc + {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25]}}, get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[25:0]};
//                     bp_l1i_valid_out_next = 1'b1;
//                     done = 1;
//                 end else if (get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx)[31:24] == 8'b01010100) begin
//                     // done = branch_taken;
//                 end
//             end
//         end
//         if (!done) begin
//             // two cases: cut short by cacheline alignment OR full super scalar. set pred PC accordingly and ensure l1i is ready
//         end
//     end else begin
//         //l1i was not valid, we will stall until it is valid
//     end
// end
