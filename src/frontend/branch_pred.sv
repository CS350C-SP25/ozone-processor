import uop_pkg::*;
import op_pkg::*;

module branch_pred #(
    parameter CACHE_LINE_WIDTH = 64,
    parameter INSTRUCTION_WIDTH = op_pkg::INSTRUCTION_WIDTH,
    parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH,
    parameter IST_ENTRIES = 1024,
    parameter BTB_ENTRIES = 128,
    parameter k = 8,
    parameter n = 8
) (
    //TODO also include inputs for GHR updates.
    input clk_in,
    input rst_N_in,
    input logic l1i_valid,
    input logic l1i_ready,
    input logic x_valid_in,  // sodais addition: this means we are resolving
    input logic pc_incorrect,  // this means that the PC that we had originally preicted was incorrect. We need to fix.
    input logic x_taken,  // sodais addition: if the branch resolved as taken or not
    input logic [63:0] x_pc,  // sodais assumption: this is from execute
    input logic [7:0] l1i_cacheline[CACHE_LINE_WIDTH-1:0],
    output logic [63:0] pred_pc,  //goes into the program counter
    output uop_branch [SUPER_SCALAR_WIDTH-1:0] decode_branch_data, //goes straight into decode. what the branches are and if the super scalar needs to be squashed
    output logic [$clog2(
SUPER_SCALAR_WIDTH+1
)-1:0] pc_valid_out,  // sending a predicted instruction address.
    output logic bp_l1i_valid_out,
    output logic [63:0] l1i_addr_out
);
  // GHR and PHT logic
  localparam int PHT_SIZE = 1 << (n + k);
  logic [k-1:0] ghr;
  logic [1:0] pht[PHT_SIZE-1:0];


  // FSM control
  logic [63:0] current_pc;  // pc register
  logic [63:0] l1i_addr_awaiting;  //address we are waiting on from cache; register
  logic bp_l1i_valid_out_next;  //wire
  uop_branch [SUPER_SCALAR_WIDTH-1:0] branch_data_next;
  logic [k-1:0] ghr_next;
  logic [1:0] pht_next[PHT_SIZE-1:0];

  // RAS
  logic ras_push;
  logic ras_push_next;
  logic ras_pop;
  logic ras_pop_next;
  logic [63:0] ras_next_push;
  logic [63:0] ras_next_push_next;
  logic [63:0] ras_top;
  logic ras_restoreTail; //ignore tail resets for now (this can be part of misprediction correction for a mildly better RAS acc)
  logic [$clog2(8)-1:0] ras_newTail;
  stack #(
      .STACK_DEPTH(8),
      .ENTRY_SIZE (64)
  ) ras (
      .clk_in(clk_in),
      .rst_N_in(rst_N_in),
      .push(ras_push),
      .pop(ras_pop),
      .pushee(ras_next_push),
      .restoreTail(ras_restoreTail),
      .newTail(ras_newTail),
      .stack_out(ras_top)
  );


  function automatic logic [INSTRUCTION_WIDTH-1:0] get_instr_bits(
      input logic [CACHE_LINE_WIDTH-1:0][7:0] cacheline, input logic [63:0] starting_addr,
      input int instr_idx);
    return cacheline[starting_addr[5:0]+(instr_idx<<2)+3:starting_addr[5:0]+(instr_idx<<2)];
  endfunction

  function automatic void pred_bcond(input logic [63:0] pc,
                                     input logic signed [18:0] offset,  // takes a signed offset
                                     output logic branch_taken, output logic pred_pc);
    // get n bits from pc
    logic [n-1:0] pc_n_bits;
    pc_n_bits = pc[n-1:0];

    // make the index
    logic [n+k-1:0] pht_index;
    pht_index = {ghr, pc_n_bits};

    logic [1:0] counter;
    counter = pht[pht_index];

    branch_taken = (counter >= 2);  // this is prob wrong

    // pred_pc
    if (branch_taken) begin
      pred_pc = pc + 64'(offset);  // this needs to be signed sooo
      // offset is 19 bits long
      // how do we add that to pc
      // pc is 64 bits
    end else begin
      pred_pc = pc + 64'h4;
    end
  endfunction

  always_ff @(posedge clk_in) begin
    if (rst_N_in) begin
      current_pc <= l1i_addr_out_next;
      l1i_addr_awaiting <= l1i_addr_out_next; //uh we could prob turn this all into cur pc but im not sure if theyll diverge
      pred_pc <= l1i_addr_out_next;  // "
      decode_branch_data <= branch_data_next;
      ghr <= ghr_next;
      pht <= pht_next;
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
    pht_next = pht;
    ghr_next = ghr;

    if (execute_in) begin
      // we got a PC and resolution from the execution phase.
      // we have gotten a valid pc from the pc, lets fetch the instruction bits from the l1i. 
      // TODO only do this on flush otherwise it should come from the output of pred_pc on this cycle
      // i think the if statement should be if branch prediction correction || initial startup
      // TODO stall if we have instruction inflight from l1ic
     if (pc_incorrect) begin
        if (x_taken) begin
            // have to call cache for the data, get_instr_bits
            current_pc = x_pc + offset // how do we get offset HERE 
            // TODO: get the L1i cache line
            
        end else begin
            // 
            current_pc = pc + 64'h4;
        end

      end
      logic [n-1:0] pc_index_update;
      pc_index_update = x_pc[n-1:0]; 

      logic [n+k-1:0] pht_index_update;
      pht_index_update = {ghr, pc_index_update}; 

      // now that we have our pht index
      // we need to see if we are gonna take it
      // and then update it

      if (x_taken) begin
        pht_next[pht_index_update] = pht[pht_index_update] + 1;
      end else if (!x_taken) begin
        pht_next[pht_index_update] = pht[pht_index_update] - 1;
      end

      ghr_next = {ghr[k-2:0], x_taken};


      // if our current guess does not match what we guessed at the beginning
      // we need to update the pc

      // how do we know what we guessed at beginning
      // can check pht entry but that could be wrong
      // can compare the  pc of the things surrounding it

      
      l1i_addr_out_next = current_pc;  // ?
      bp_l1i_valid_out_next = 1'b1; // gets the cacheline
      // how do we wait for next clock cycle
    end else begin
      if (l1i_valid) begin // we got the instruction bits back. predecode, update ras, pred_pc, look up ghr, etc
        done = 1'b0;
        for (int instr_idx = 0; instr_idx < SUPER_SCALAR_WIDTH; instr_idx++) begin
          if (l1i_addr_awaiting[5:0]+(instr_idx<<2) <= CACHE_LINE_WIDTH - INSTRUCTION_WIDTH && !done) begin
            if (get_instr_bits(
                    l1i_cacheline, l1i_addr_awaiting, instr_idx
                ) [31:21] == 11'b11010110010) begin  //RET
              // pop off RAS, if RAS is empty, sucks to be us. 
              branch_data_next[instr_idx].branch_target = ras_top;
              //these 2 fields are the register put together (its a union but quartus doesnt support unions)
              branch_data_next[instr_idx].condition =
                  get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [4:1];
              branch_data_next[instr_idx].predict_taken =
                  get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [0];
              pc_valid_out_next = instr_idx + 1; //this is the last relevant address we have branched away from this cacheline (prob)
              l1i_addr_out_next = ras_top;  //fetch the next address
              ras_pop_next = 1'b1;
              done = 1;
            end else if (get_instr_bits(
                    l1i_cacheline, l1i_addr_awaiting, instr_idx
                ) [31:26] == 6'b000101) begin  //B
              // decode the predicted PC and do the add
              // store branching info, ignore the remaining
              // set branch data for this index
              branch_data_next[instr_idx].branch_target = pc +
                  {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [25]}},
                   get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [25:0]} +
                  (instr_idx << 2);
              pc_valid_out_next = instr_idx + 1; //this is the last relevant address we have branched away from this cacheline (prob)
              // set the next l1i target to the predicted PC
              l1i_addr_out_next = pc +
                  {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [25]}},
                   get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [25:0]} +
                  (instr_idx << 2);
              done = 1;
            end else if (get_instr_bits(
                    l1i_cacheline, l1i_addr_awaiting, instr_idx
                ) [31:26] == 6'b100101) begin  // BL (same as B but we need to push to RAS)
              // push to RAS l1i_addr_awaiting[5:0]+(instr_idx<<2) + 4
              ras_push_next = 1'b1;
              ras_next_push_next = l1i_addr_awaiting[5:0] + (instr_idx << 2) + 4;  // return address
              // decode the predicted PC and do the add
              // store branching info, ignore the remaining
              // set branch data for this index
              branch_data_next[instr_idx].branch_target = pc +
                  {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [25]}},
                   get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [25:0]} +
                  (instr_idx << 2);
              pc_valid_out_next = instr_idx + 1; //this is the last relevant address we have branched away from this cacheline (prob)
              // set the next l1i target to the predicted PC
              l1i_addr_out_next = pc +
                  {{38{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [25]}},
                   get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [25:0]} +
                  (instr_idx << 2);
              done = 1;
            end else if (get_instr_bits(
                    l1i_cacheline, l1i_addr_awaiting, instr_idx
                ) [31:24] == 8'b01010100) begin
              // done = branch_taken;
              // for now lets just always assume branch not taken we can adjust this later with a GHR and PHT
              branch_data_next[instr_idx].branch_target = pc +
                  {{45{get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [23]}},
                   get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [23:5]} +
                  (instr_idx << 2);
              branch_data_next[instr_idx].condition =
                  get_instr_bits(l1i_cacheline, l1i_addr_awaiting, instr_idx) [3:0];
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
