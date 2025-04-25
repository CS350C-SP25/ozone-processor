`include "../util/uop_pkg.sv"
`include "../util/op_pkg.sv"
`include "../util/stack.sv"
`include "./cache/l0_instr_cache.sv"
import uop_pkg::*;
import op_pkg::*;

module branch_pred #(
  parameter CACHE_LINE_WIDTH = 64,
  parameter INSTRUCTION_WIDTH = op_pkg::INSTRUCTION_WIDTH,
  parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH,
  parameter IST_ENTRIES = 1024,
  parameter BTB_ENTRIES = 128,
  parameter GHR_K = 8,
  parameter PHT_N = 8,
  parameter L0_WAYS = 8
) (
  // TODO also include inputs for GHR updates.
  input clk_in,
  input rst_N_in,
  input logic l1i_valid,
  input logic l1i_ready,
  input logic x_bcond_resolved,
  input logic x_pc_incorrect,  // this means that the PC that we had originally predicted was incorrect. We need to fix.
  input logic x_taken,  // if the branch resolved as taken or not -- to update PHT and GHR
  input logic [63:0] x_pc, // pc that is currently in the exec phase (the one that just was resolved)
  input logic [18:0] x_correction_offset, // the offset of the correction from x_pc (could change this to be just the actual correct PC instead ??)
  input logic l1i_cacheline [CACHE_LINE_WIDTH*8-1:0],
  output logic [63:0] pred_pc,  //goes into the fetch
  output uop_branch  decode_branch_data [SUPER_SCALAR_WIDTH-1:0], //goes straight into decode. what the branches are and if the super scalar needs to be squashed
  output logic pc_valid_out,  // sending a predicted instruction address. 
  output logic bp_l1i_valid_out, //fetch uses this + pc valid out to determine if waiting for l1i or 
  output logic bp_l0_valid, // this is the l0 cacheline valid ???
  output logic [63:0] l1i_addr_out, // this is the address we are sending to l1i
  output logic l0_cacheline [CACHE_LINE_WIDTH*8-1:0] // this gets fed to fetch
);
  // GHR and PHT logic
  localparam int PHT_SIZE = 1 << (PHT_N + GHR_K);
  logic [GHR_K-1:0] ghr;
  logic [1:0] pht[PHT_SIZE-1:0];


  // FSM control
  logic [63:0] current_pc;  // pc register
  logic [63:0] l1i_addr_awaiting;  //address we are waiting on from cache; register
  uop_branch branch_data_next [SUPER_SCALAR_WIDTH-1:0];
  uop_branch branch_data_buffer [SUPER_SCALAR_WIDTH-1:0];
  uop_branch branch_data_buffer_next [SUPER_SCALAR_WIDTH-1:0];
  logic l0_cacheline_next [CACHE_LINE_WIDTH*8-1:0]; // wire (saved to the fetch out and local)
  logic l0_cacheline_unsplit [CACHE_LINE_WIDTH * 8-1:0]; // wire (saved to the fetch out and local)
  logic [7:0] l0_cacheline_local [CACHE_LINE_WIDTH-1:0]; // register
  logic l1_cacheline_unsplit [CACHE_LINE_WIDTH * 8-1:0]; 
  logic [7:0] l1_cacheline_local [CACHE_LINE_WIDTH-1:0]; // register
  logic l0_hit;
  logic pc_valid_out_next;
  logic [GHR_K-1:0] ghr_next;
  logic [1:0] pht_next[PHT_SIZE-1:0];
  logic instructions_inflight;
  logic instructions_inflight_next;
  logic [64:0] l1i_q;
  logic [64:0] l1i_q_next;
  logic [63:0] l1i_addr_out_next; // ???? 


  assign l0_cacheline_local[0] = l0_cacheline_unsplit[63:0];
  assign l0_cacheline_local[1] = l0_cacheline_unsplit[64*1+:64];
  assign l0_cacheline_local[2] = l0_cacheline_unsplit[64*2+:64];
  assign l0_cacheline_local[3] = l0_cacheline_unsplit[64*3+:64];
  assign l0_cacheline_local[4] = l0_cacheline_unsplit[64*4+:64];
  assign l0_cacheline_local[5] = l0_cacheline_unsplit[64*5+:64];
  assign l0_cacheline_local[6] = l0_cacheline_unsplit[64*6+:64];
  assign l0_cacheline_local[7] = l0_cacheline_unsplit[64*7+:64];

  assign l1_cacheline_local[0] = l1_cacheline_unsplit[63:0];
  assign l1_cacheline_local[1] = l1_cacheline_unsplit[64*1+:64];
  assign l1_cacheline_local[2] = l1_cacheline_unsplit[64*2+:64];
  assign l1_cacheline_local[3] = l1_cacheline_unsplit[64*3+:64];
  assign l1_cacheline_local[4] = l1_cacheline_unsplit[64*4+:64];
  assign l1_cacheline_local[5] = l1_cacheline_unsplit[64*5+:64];
  assign l1_cacheline_local[6] = l1_cacheline_unsplit[64*6+:64];
  assign l1_cacheline_local[7] = l1_cacheline_unsplit[64*7+:64];

  
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


  l0_instruction_cache #(
    .SETS(8),
    .LINE_SIZE_BYTES(64),
    .A(1),
    .PC_SIZE(64)
  ) l0 (
    .l1i_pc(l1i_addr_awaiting),  // address we check cache for
    .l1_valid(l1i_valid),  // if the l1 is ready to give us data
    .l1_data(l1i_cacheline),  // data coming in from L1
    .bp_pc(l1i_addr_out_next), // ?
    .bp_pred_pc(l1i_addr_out_next),        // the next pc of the bp (this is what we are checking hit for actually)
    .cache_line(l0_cacheline_next),  // data output to branch predictor
    .cache_hit(l0_hit)  // high on a hit, low on a miss (this is for the next cycle)
  );


  function automatic logic [INSTRUCTION_WIDTH-1:0] get_instr_bits(
    input logic [CACHE_LINE_WIDTH-1:0][7:0] cacheline, input logic [63:0] starting_addr,
    input int instr_idx);
 
      // wont work bc those each side not constant at compile time
      // cacheline[starting_addr[5:0]+(instr_idx<<2)+3:starting_addr[5:0]+(instr_idx<<2)];
      // TODO is that the same lol?
      return cacheline[starting_addr[5:0] + (instr_idx << 2) +: 4]; // i think this is the same?

  endfunction
 
  // PRE - DECODE
  function automatic void process_pc (
  input logic [7:0] cacheline[CACHE_LINE_WIDTH-1:0], 
  input logic [63:0] pc,
  input logic [PHT_N+GHR_K-1:0] pht_index,
  output logic [63:0] l1i_addr_out_next
  );
  logic done = 1'b0;
  // TODO multiply by 4 and handle sign extensions
  for (int instr_idx = 0; instr_idx < SUPER_SCALAR_WIDTH; instr_idx++) begin
    if (current_pc[5:0]+(instr_idx<<2) <= CACHE_LINE_WIDTH - INSTRUCTION_WIDTH && !done) begin
      if (get_instr_bits(
          cacheline, current_pc, instr_idx
        ) [31:21] == 11'b11010110010) begin  // RET 
      // pop off RAS, if RAS is empty, sucks to be us. 
      branch_data_next[instr_idx].branch_target = ras_top;
      // these 2 fields are the register put together (its a union but quartus doesnt support unions)
      branch_data_next[instr_idx].condition =
        get_instr_bits(cacheline, current_pc, instr_idx) [4:1];
      branch_data_next[instr_idx].predict_taken =
        get_instr_bits(cacheline, current_pc, instr_idx) [0];
      l1i_addr_out_next = ras_top;  //fetch the next address
      ras_pop_next = 1'b1;
      done = 1;
      end else if (get_instr_bits(
          cacheline, current_pc, instr_idx
        ) [31:26] == 6'b000101) begin  // B
      // decode the predicted PC and do the add
      // store branching info, ignore the remaining
      // set branch data for this index
      branch_data_next[instr_idx].branch_target = pc +
    ({{38{get_instr_bits(cacheline, current_pc, instr_idx)[25]}},
      get_instr_bits(cacheline, current_pc, instr_idx)[25:0]} << 2) +
    (instr_idx << 2); // MULTIPLIED BY FOUR!!!

      // set the next l1i target to the predicted PC
      l1i_addr_out_next = pc +
        {{38{get_instr_bits(cacheline, current_pc, instr_idx) [25]}},
        get_instr_bits(cacheline, current_pc, instr_idx) [25:0]} +
        (instr_idx << 2);
      done = 1;
      end else if (get_instr_bits(
          cacheline, current_pc, instr_idx
        ) [31:26] == 6'b100101) begin  // BL (same as B but we need to push to RAS)
      // push to RAS current_pc[5:0]+(instr_idx<<2) + 4
      ras_push_next = 1'b1;
      ras_next_push_next = current_pc[5:0] + (instr_idx << 2) + 4;  // return address
      // decode the predicted PC and do the add
      // store branching info, ignore the remaining
      // set branch data for this index
      branch_data_next[instr_idx].branch_target = pc +
    ({{38{get_instr_bits(cacheline, current_pc, instr_idx)[25]}},
      get_instr_bits(cacheline, current_pc, instr_idx)[25:0]} << 2) +
    (instr_idx << 2); // MULTIPLIED BY
  
    // set next to pred pc
    l1i_addr_out_next = pc +
        ({{38{get_instr_bits(cacheline, current_pc, instr_idx)[25]}},
          get_instr_bits(cacheline, current_pc, instr_idx)[25:0]} << 2) +
        (instr_idx << 2);

      done = 1;
      end else if (get_instr_bits(
          cacheline, current_pc, instr_idx
        ) [31:24] == 8'b01010100) begin // assumption is bcond
      // done = branch_taken;
      // for now lets just always assume branch not taken we can adjust this later with a GHR and PHT
      // offset is 5-23
           branch_data_next[instr_idx].branch_target = pc +
    ({{45{get_instr_bits(cacheline, current_pc, instr_idx)[23]}},
      get_instr_bits(cacheline, current_pc, instr_idx)[23:5]} << 2) +
    (instr_idx << 2); // MULTIPLIED BY FOUR
      branch_data_next[instr_idx].condition =
        get_instr_bits(cacheline, current_pc, instr_idx) [3:0];
      branch_data_next[instr_idx].predict_taken = pht[pht_index] > 1; 
      end
    end
  end
  if (!done) begin
    // two cases: cut short by cacheline alignment OR full super scalar. set pred PC accordingly and ensure l1i is ready
    l1i_addr_out_next = current_pc + current_pc[5:0] <= 64 - (SUPER_SCALAR_WIDTH << 2) ? SUPER_SCALAR_WIDTH << 2 : (64 - current_pc[5:0]) >> 2;
  end
  endfunction


  always_ff @(posedge clk_in) begin
  if (rst_N_in) begin //not reset. this is the good stuff
    if (pc_valid_out_next) begin // we processed instruction bits. (data from the cache was returned)
    current_pc <= l1i_addr_out_next; 
    pred_pc <= l1i_addr_out_next;
    l1i_addr_out <= l1i_addr_out_next;
    bp_l1i_valid_out <= ~l0_hit; // if we hit in l0 for this new predicted PC then we dont send to l1i;
    instructions_inflight <= ~l0_hit; // """
    decode_branch_data <= branch_data_next; // this is the data we just decoded, we will pass this to decode for better decoding
    end else begin
    current_pc <= current_pc;
    pred_pc <= pred_pc;
    bp_l1i_valid_out <= 1'b0;
    instructions_inflight <= instructions_inflight;
    decode_branch_data <= branch_data_next;
    end
    pc_valid_out <= pc_valid_out_next;
    ghr <= ghr_next;
    pht <= pht_next;
    l1_cacheline_unsplit <= l1i_cacheline;
    l0_cacheline_unsplit <= l0_cacheline_next;
    l0_cacheline <= l0_cacheline_next;
    bp_l0_valid <= pc_valid_out_next & l0_hit;
  end else begin
    current_pc <= '0;
    pred_pc <= '0;
    pc_valid_out <= '0;
    l1i_addr_out <= '0;
    bp_l1i_valid_out <= '0;
    instructions_inflight <= 1'b0;
    // decode_branch_data <= '0; //  this is an array
    // l0_cacheline_local <= '0; // this is an array
    foreach (decode_branch_data[i])
      decode_branch_data[i] <= '0;

    foreach (l0_cacheline_local[i])
      l0_cacheline_local[i] <= 8'h00;

    foreach (decode_branch_data[i])
      decode_branch_data[i] <= '0;

    foreach (l0_cacheline[i])
      l0_cacheline[i] <= 8'h00;

    ghr <= '0;
    pht <= '0;
  end
  end 

  // todo ready valid for bp
  // todo sign extend
  // todo comp erfrors

  logic [PHT_N+GHR_K-1:0] pht_index_update;
  logic [PHT_N-1:0] pc_index_update;
  always_comb begin
  pht_next = pht;
  ghr_next = ghr;
   
  if (x_bcond_resolved) begin
    // we got a PC and resolution from the execution phase.
    // we have gotten a valid pc from the pc, lets fetch the instruction bits from the l1i. 
    // TODO only do this on flush otherwise it should come from the output of pred_pc on this cycle
    // i think the if statement should be if branch prediction correction || initial startup
    // TODO stall if we have instruction inflight from l1ic

    pc_index_update = x_pc[PHT_N-1:0];
    pht_index_update = {ghr, pc_index_update};

    // now that we have our pht index
    // we need to see if we are gonna take it
    // and then update it

    if (x_taken) begin
    pht_next[pht_index_update] = (pht[pht_index_update] + 1) == 0 ? pht[pht_index_update] : pht[pht_index_update] + 1; // make sure overflow doeesnt happen
    end else if (!x_taken) begin
    pht_next[pht_index_update] = pht[pht_index_update] == 0 ? 0 : pht[pht_index_update] - 1; // prevent underflow
    end

    ghr_next = {ghr[GHR_K-2:0], x_taken};
    // how do we wait for next clock cycle
  end

  if (x_pc_incorrect) begin
    if (instructions_inflight && !l1i_valid) begin
      // we have instructions in flight and they arent valid we need to stall until they expire we need to supress the next l1i return
      l1i_q_next = {1'b1, x_pc + {{45{x_correction_offset[18]}}, x_correction_offset}};
    end else begin
       l1i_addr_out_next = {x_pc + {{45{x_correction_offset[18]}}, x_correction_offset}};
       pc_valid_out_next = 1'b1;
    end
  end else begin
    if (l1i_valid && l1i_q[64]) begin // shouldnt it be l0? im confused
      l1i_addr_out_next = l1i_q[63:0];
      l1i_q_next = '0; // we skip this guy and now we can send proccess this current PC
      pc_valid_out_next = 1'b1;
    end else if (l1i_valid) begin // we got the instruction bits back. predecode, update ras, pred_pc, look up ghr, etc
      // this processes a cacheline from l1i
      // TODO dont directly send pred pc to l1i, check if the pred pc tag matches. 
process_pc(
  .cacheline(l1i_cacheline),
  .pc(current_pc),
  .pht_index({ghr, current_pc[PHT_N-1:0]}),
  .l1i_addr_out_next(l1i_addr_out_next)
);
      pc_valid_out_next = 1'b1;
    end else if (!instructions_inflight) begin
      //l1i was not valid, we check if any instructions are in flight if so stall otherwise we must be in l0.
process_pc(
  .cacheline(l0_cacheline_local),
  .pc(current_pc),
  .pht_index({ghr, current_pc[PHT_N-1:0]}),
  .l1i_addr_out_next(l1i_addr_out_next)
);
      pc_valid_out_next = 1'b1;
    end
  end
  end
endmodule
