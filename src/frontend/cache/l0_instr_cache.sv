/** 
* This cache is meant to be completely combinational -- 0 cycle latency, but also req data to the L1 when requested.
*/


module l0_instruction_cache #(
    parameter int SETS = 8,
    parameter int LINE_SIZE_BYTES = 64,
    parameter int A = 1,
    parameter int PC_SIZE = 64
) (
    input logic [PC_SIZE-1:0] l1i_pc,  // address we check cache for
    input logic l1_valid,  // if the l1 is ready to give us data
    input logic [LINE_SIZE_BYTES*8-1:0] l1_data,  // data coming in from L1
    input logic [PC_SIZE-1:0] bp_pc, // ????
    input logic [PC_SIZE-1:0] bp_pred_pc, // ?? 

    output logic [LINE_SIZE_BYTES*8-1:0] cache_line,  // data output to branch predictor
    output logic cache_hit  // high on a hit, low on a miss
);

  localparam int BLOCK_OFFSET_BITS = $clog2(LINE_SIZE_BYTES);
  localparam int SET_INDEX_BITS = $clog2(SETS);
  localparam int TAG_BITS = PC_SIZE - SET_INDEX_BITS - BLOCK_OFFSET_BITS;

  // Data array    
  typedef logic [LINE_SIZE_BYTES * 8-1:0] cache_line_t;
  typedef cache_line_t cache_data_way_t[SETS-1:0];
  cache_data_way_t cache_data[A-1:0];

  cache_line_t cache_line_temp;

  // Tag Entry
  typedef struct packed {
    logic valid;
    logic dirty;
    logic [3:0] pid;
    logic [TAG_BITS-1:0] tag;
  } tag_entry;


  typedef tag_entry tag_way[SETS-1:0];
  tag_way                        tag_array      [A-1:0];
  tag_entry                      tag_entry_temp;

  // address breakdown; for readability's sake
  logic     [SET_INDEX_BITS-1:0] l1i_index;
  logic     [      TAG_BITS-1:0] l1i_tag;
  logic     [SET_INDEX_BITS-1:0] bp_index;
  logic     [      TAG_BITS-1:0] bp_tag;
  logic     [SET_INDEX_BITS-1:0] pred_index;
  logic     [      TAG_BITS-1:0] pred_tag;
  
  
  assign l1i_index = l1i_pc[BLOCK_OFFSET_BITS+:SET_INDEX_BITS];
  assign l1i_tag   = l1i_pc[PC_SIZE-1:BLOCK_OFFSET_BITS+SET_INDEX_BITS];
  assign pred_index = bp_pred_pc[BLOCK_OFFSET_BITS+:SET_INDEX_BITS];
  assign pred_tag   = bp_pred_pc[PC_SIZE-1:BLOCK_OFFSET_BITS+SET_INDEX_BITS];

  // outputs:
  assign cache_hit = tag_array[0][pred_index].valid & tag_array[0][pred_index].tag == pred_tag;
  assign cache_line = cache_data[0][pred_index];

  // update l0 with l1i information
  always_latch begin
    if (l1_valid) begin  // if data came in from the l1 cache, we update our data in this cache.
      cache_data[0][l1i_index] = l1_data;  // assumption index the same
      tag_array[0][l1i_index].valid = 1'b1;
      tag_array[0][l1i_index].tag = l1i_tag;
    end
  end

endmodule
