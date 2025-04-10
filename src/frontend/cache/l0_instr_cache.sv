/** 
* This cache is meant to be completely combinational -- 0 cycle latency, but also req data to the L1 when requested.
*/

/**

*/

module l0_instruction_cache #(
    parameter int SETS = 8,
    parameter int LINE_SIZE_BYTES = 64,
    parameter int A = 1,
    parameter int PC_SIZE = 64
) (
    input logic [PC_SIZE-1:0] pc,  // address we check cache for
    input logic l1_ready,  // if the l1 is ready to receive
    input logic l1_valid,  // if the l1 is ready to give us data
    input logic [LINE_SIZE_BYTES*8-1:0] l1_data,  // data coming in from L1

    output logic [LINE_SIZE_BYTES*8-1:0] cache_line,  // data output to branch predictor
    output logic cache_hit,  // high on a hit, low on a miss

    output logic l1_out_ready,  // if we are ready to receive l1 data
    output logic l1_out_valid   // if we are ready to give l1 data

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


  typedef tag_entry tag_way[NUM_SETS-1:0];
  tag_way tag_array[A-1:0];
  tag_entry tag_entry_temp;


  assign index = pc[BLOCK_OFFSET_BITS+:SET_INDEX_BITS];
  assign tag   = pc[PC_SIZE-1:BLOCK_OFFSET_BITS+SET_INDEX_BITS];

  always_comb begin : l0_combinational_block
    // default vals
    hit = 1'b0;
    l1_out_valid = 1'b0;
    l1_out_ready = 1'b0;
    cache_line = '0;
    // lookup
    if (tag_array[index].valid && tag_array[index].tag == tag) begin
      // cache hit
      cache_hit  = 1'b1;
      cache_line = cache_data[index];
    end else begin
      // cache miss

      l1_out_valid = 1'b1;  // READY VALID LOGIC SHAKEY, ONLY ONE LATCHES SO 
                            // WE WONT NEED BOTH, BUT JUST IN CASE ITS HERE
      l1_out_ready = 1'b1;  // we can only send one at a time 
    end

    if (l1_valid && l1_out_ready) begin
      cache_data[index] = l1_data;
      tag_array[index].valid = 1'b1;
      tag_array[index].tag = tag;
      cache_line = cache_data[index];
    end
  end
endmodule
