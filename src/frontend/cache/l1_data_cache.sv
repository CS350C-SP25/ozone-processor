// /*
//  The L1 Data cache is expected to be:
//  - PIPT. However the addresses it accepts are virtual, so it must interface with
//    the MMU
//  - Non-blocking. Meaning a miss should not block the cache from recieving new inputs.
//    This will require use of the MSHRs, which store their addresses using CAMs.
//  - Write-back. Dirty cache lines should be written back on an eviction.
//  It is important to note that a cache line returning from a lower-level cache
//  may cause an eviction.
//  - Should a cache perform an eviction, it will need to writeback to memory. This
//    is different from a regular write, because nothing is expected to be returned from
//    DRAM.
//  - Evicting can be thought of as a special case of a write which does not return a
//    cache line.
//  - Storing the instructions tags in the MSHR is necessary. Consider that there
//    could be 3 different writes in the LSQ. When returning a write, we
//  A fun issue is that the LSU expects a virtual address to be returned to it, but
//  this is a PIPT cache. Maybe the MSHRs can help?
//  */

// // all this module needs to do is keep tracking mshr matching, that's all.
// module l1_data_cache #(
//     parameter int A = 3,
//     parameter int B = 64,
//     parameter int C = 1536,
//     parameter int PADDR_BITS = 22,
//     parameter int MSHR_COUNT = 4,
//     parameter int TAG_BITS = 10
// ) (
//     // Inputs from LSU
//     input logic clk_in,
//     input logic rst_N_in,
//     input logic cs_N_in,
//     input logic flush_in,
//     input logic lsu_valid_in,
//     input logic lsu_ready_in,
//     input logic [63:0] lsu_addr_in,
//     input logic [63:0] lsu_value_in,
//     input logic [TAG_BITS-1:0] lsu_tag_in,
//     input logic lsu_we_in,
//     // signals that go to LSU
//     output logic lsu_valid_out,
//     output logic lsu_ready_out,
//     output logic [63:0] lsu_addr_out,
//     output logic [63:0] lsu_value_out,
//     output logic lsu_write_complete_out,
//     output logic [TAG_BITS-1:0] lsu_tag_out,
//     // Inputs from LLC
//     input logic lc_ready_in,
//     input logic lc_valid_in,
//     input logic [PADDR_BITS-1:0] lc_addr_in,
//     input logic [8*B-1:0] lc_value_in,
//     // signals that go to LLC
//     output logic lc_valid_out,
//     output logic lc_ready_out,
//     output logic [PADDR_BITS-1:0] lc_addr_out,
//     output logic [8*B-1:0] lc_value_out,
//     output logic lc_we_out
// );

//   localparam PADDR_SIZE = PADDR_BITS;
//   typedef struct packed {
//     logic [PADDR_SIZE-1:0]                 paddr;           // address
//     logic [PADDR_BITS-1:BLOCK_OFFSET_BITS] no_offset_addr;  // address without offset
//     logic                                  we;              // write enable
//     logic [63:0]                           data;            // if writing data, the store value
//     logic [TAG_BITS-1:0]                   tag;             // processor tag, not memory addr tag
//     logic                                  valid;
//   } mshr_entry_t;

//   mshr_entry_t                  mshr_entries [MSHR_COUNT-1:0];

//   // Add enqueue and dequeue signals for each MSHR queue
//   logic        [MSHR_COUNT-1:0] mshr_enqueue;
//   logic        [MSHR_COUNT-1:0] mshr_dequeue;
//   mshr_entry_t                  mshr_outputs [MSHR_COUNT-1:0];
//   logic        [MSHR_COUNT-1:0] mshr_empty;
//   logic        [MSHR_COUNT-1:0] mshr_full;





//   typedef enum logic [3:0] {
//     IDLE,
//     SEND_REQ_LC,
//     SEND_RESP_HC,
//     CHECK_MSHR,
//     READ_CACHE,
//     WRITE_CACHE,
//     WAIT_CACHE,
//     WAIT_CACHE_READ,
//     WAIT_MSHR,
//     CLEAR_MSHR,
//     EVICT,
//     WRITE_FROM_MSHR,
//     READ_FROM_MSHR,
//     COMPLETE_WRITE,
//     COMPLETE_READ,
//     FLUSH
//   } states;

//   states cur_state, next_state;

//   reg flush_in_reg;
//   reg lsu_valid_in_reg;
//   reg lsu_ready_in_reg;
//   reg [63:0] lsu_addr_in_reg;
//   reg [63:0] lsu_value_in_reg;
//   reg [TAG_BITS-1:0] lsu_tag_in_reg;
//   reg lsu_we_in_reg;
//   reg lc_ready_in_reg;
//   reg lc_valid_in_reg;
//   reg [PADDR_BITS-1:0] lc_addr_in_reg;
//   reg [8*B-1:0] lc_value_in_reg;

//   reg lsu_valid_out_reg;
//   reg lsu_ready_out_reg;
//   reg [63:0] lsu_addr_out_reg;
//   reg [63:0] lsu_value_out_reg;
//   reg [TAG_BITS-1:0] lsu_tag_out_reg;
//   reg lsu_write_complete_out_reg;
//   reg lc_valid_out_reg;
//   reg lc_ready_out_reg;
//   reg [PADDR_BITS-1:0] lc_addr_out_reg;
//   reg [8*B-1:0] lc_value_out_reg;
//   reg lc_we_out_reg;

//   reg is_blocked_reg;
//   // logic [TAG_BITS-1:0] tag_reg;
//   // logic [TAG_BITS-1:0] tag_comb;

//   logic lsu_valid_out_comb;
//   logic lsu_ready_out_comb;
//   logic [63:0] lsu_addr_out_comb;
//   logic [63:0] lsu_value_out_comb;
//   logic lsu_write_complete_out_comb;
//   logic lc_valid_out_comb;
//   logic lc_ready_out_comb;
//   logic [PADDR_BITS-1:0] lc_addr_out_comb;
//   logic [8*B-1:0] lc_value_out_comb;
//   logic lc_we_out_comb;

//   logic is_blocked_comb;

//   localparam int BLOCK_OFFSET_BITS = $clog2(B);
//   logic [PADDR_BITS-1:0] cur_addr;
//   logic [PADDR_BITS-1:BLOCK_OFFSET_BITS] no_offset_addr;

//   logic [TAG_BITS-1:0] lsu_tag_out_comb;

//   assign cur_addr = lsu_addr_in_reg[PADDR_BITS-1:0];
//   assign no_offset_addr = lsu_addr_in_reg[PADDR_BITS-1:BLOCK_OFFSET_BITS];

//   /* MSHR Combinational Variables */
//   logic found;
//   int   pos;
//   logic isFree;
//   int   freePos;
//   logic needToAdd;
//   int   wait_comb;
//   int   wait_reg;

//   always_comb begin : l1d_combinational_logic
//     lsu_valid_out_comb = '0;
//     lsu_ready_out_comb = 1'b0;
//     lsu_addr_out_comb = lsu_addr_out_reg;
//     lsu_value_out_comb = lsu_value_out_reg;
//     lsu_write_complete_out_comb = 1'b0;
//     lc_valid_out_comb = 1'b0;
//     lc_ready_out_comb = 1'b0;
//     lc_addr_out_comb = lc_addr_out_reg;
//     lc_value_out_comb = lc_value_out_reg;
//     lc_we_out_comb = 1'b0;
//     next_state = cur_state;
//     needToAdd = 1;
//     is_blocked_comb = is_blocked_reg;
//     wait_comb = wait_reg;

//     /* Cache Inputs */
//     cache_flush_next = 0;
//     cache_hc_valid_next = 0;
//     cache_hc_ready_next = 0;
//     cache_hc_addr_next = cache_hc_addr_reg;
//     cache_hc_value_next = lsu_value_in_reg;
//     cache_hc_we_next = lsu_we_in_reg;
//     cache_cl_next = 0;
//     cache_lc_valid_in_next = 0;
//     cache_lc_ready_in_next = 0;
//     cache_lc_addr_in_next = lc_addr_in_reg;
//     cache_lc_value_in_next = lc_value_in_reg;

//     lsu_tag_out_comb = lsu_tag_out_reg;

//     for (int i = 0; i < MSHR_COUNT; i++) begin
//       mshr_enqueue[i] = 1'b0;
//       mshr_entries[i] = '0;
//       mshr_dequeue[i] = 1'b0;
//     end

//     found = 0;
//     pos = 0;
//     isFree = 0;
//     freePos = 0;

//     case (cur_state)
//       IDLE: begin

//         if (lc_valid_in_reg) begin
//           lc_ready_out_comb = 1;
//         end else if (lsu_valid_in_reg) begin
//           // check if all MSHRs are full, if they are, we can't accept this request (womp womp)
//           for (int i = 0; i < MSHR_COUNT; i++) begin
//             if (!mshr_outputs[i].valid || (mshr_outputs[i].valid && mshr_outputs[i].no_offset_addr == no_offset_addr)) begin
//               // there is a free mshr, we can take the request
//               lsu_ready_out_comb = 1;
//             end
//           end
//         end

//         lsu_tag_out_comb = lsu_tag_in_reg;

//         wait_comb = 5;

//         if (flush_in) begin
//           next_state = FLUSH;
//         end else if (lc_valid_in_reg || (lsu_ready_out_comb && lsu_valid_in_reg)) begin
//           next_state = (lc_valid_in_reg || lsu_we_in_reg) ? WRITE_CACHE : READ_CACHE;
//         end
//       end

//       READ_CACHE: begin
//         $display("ATTEMPTING TO READ CACHE DATA");
//         cache_hc_addr_next = cur_addr;
//         cache_hc_valid_next = 1;

//         next_state = (cache_hc_ready_out_reg) ? WAIT_CACHE : cur_state;
//       end

//       WRITE_CACHE: begin
//         if (lc_valid_in_reg) begin
//           $display("WRITING FROM LC");
//           cache_lc_valid_in_next = (cache_hc_ready_out_reg || cache_lc_ready_out_reg) ? 0 : 1;
//           cache_lc_value_in_next = lc_value_in_reg;
//           cache_lc_addr_in_next  = lc_addr_in_reg;

//         end else begin
//           $display("WRITING FROM LSU");
//           cache_hc_valid_next = 1;
//           cache_hc_we_next = (cache_hc_ready_out_reg || cache_lc_ready_out_reg) ? 0 : 1;
//           cache_hc_value_next = lsu_value_in_reg;
//           cache_hc_addr_next = cur_addr;
//         end

//         next_state = (cache_hc_ready_out_reg || cache_lc_ready_out_reg) ? WAIT_CACHE : cur_state;
//       end

//       WAIT_CACHE: begin
//         cache_hc_valid_next = 0;
//         cache_lc_valid_in_next = 0;
//         // if this was a write from lower cache, we only hae to worry about evictions, not about any of the other stuff
//         if (lc_valid_in_reg) begin
//           // was a write from the lower cache, either evict, or continue to clearing mshr
//           next_state = CLEAR_MSHR;
//           if (cache_lc_valid_out_reg) begin
//             // eviction! handle eviction and then clear MSHR for this addr
//             next_state = EVICT;
//           end else begin
//             // no eviction! we can simply go back to MSHRs and do the whole queue
//           end
//         end else if (cache_lc_valid_out_reg) begin
//           $display("miss detected on write");
//           // Requesting data from lower cache -- this is a MISS or EVICTION, GOTO MISS STATUS HANDLE REGISTERS
//           cache_lc_ready_in_next = 1;  // complete transcation

//           next_state = CHECK_MSHR;

//           if (cache_we_out_reg) begin
//             // this is an EVICTION
//             lc_value_out_comb = cache_lc_value_out_reg;
//             lc_addr_out_comb = cache_lc_addr_out_reg;
//             lc_we_out_comb = 1;

//             next_state = EVICT;
//           end
//         end else if (cache_hc_valid_out_reg) begin
//           // READ HIT! We can move to sending data back to the top
//           cache_hc_ready_next = 1;  // complete transcation
//           lsu_value_out_comb = cache_hc_value_out_reg;
//           next_state = SEND_RESP_HC;
//         end else begin
//           // was a write from HC but was completed without problem
//           wait_comb -= 1;
//           if (wait_comb == 0) begin
//             lsu_write_complete_out_comb = 1;
//             next_state = IDLE;
//           end
//         end
//       end


//       CHECK_MSHR: begin
//         // go through every MSHR and check if we already have one
//         for (int i = 0; i < MSHR_COUNT; i++) begin
//           if (mshr_outputs[i].no_offset_addr == no_offset_addr) begin
//             found = 1;
//             pos   = i;
//           end

//           if (!mshr_outputs[i].valid) begin // checks the top of the queue of any mshr, if ts not valid, mshr is free
//             isFree  = 1;
//             freePos = i;
//           end
//         end

//         cache_hc_valid_next = 0;
//         cache_lc_valid_in_next = 0;
//         cache_hc_we_next = 0;


//         // only add if there is no MSHR with the current block address
//         if (!found) begin
//           $display("primary miss!");
//           // PRIMARY MISS -- let's make a new miss queue
//           // add to the MSHR
//           if (isFree) begin
//             // there is a free MSHR, we will update the queue
//             mshr_entries[freePos].valid = 1;
//             mshr_entries[freePos].paddr = cur_addr;
//             mshr_entries[freePos].we = lsu_we_in_reg;
//             mshr_entries[freePos].data = lsu_value_in_reg;
//             mshr_entries[freePos].tag = lsu_tag_in_reg;
//             mshr_entries[freePos].no_offset_addr = no_offset_addr;

//             mshr_enqueue[freePos] = 1;
//             next_state = SEND_REQ_LC;
//           end

//           // now, we shall send a request for the cache line
//         end else begin
//           // SECONDARY MISS -- let's add to the miss queue
//           $display("secondary miss!");
//           next_state = IDLE;
//           if (!mshr_full[pos]) begin
//             if (lsu_we_in_reg) begin
//               // if this is a write, we will add it to the end of the queue
//               // queue is not full, we can add
//               mshr_entries[pos].valid = 1;
//               mshr_entries[pos].paddr = cur_addr;
//               mshr_entries[pos].we = lsu_we_in_reg;
//               mshr_entries[pos].data = lsu_value_in_reg;
//               mshr_entries[pos].tag = lsu_tag_in_reg;
//               mshr_entries[pos].no_offset_addr = no_offset_addr;

//               mshr_enqueue[pos] = 1;

//               $display("added to mshr now going to request from LC");
//               next_state = SEND_REQ_LC;
//             end else begin
//               // TODO: FWD AND ALSO CHECKING THE ENTIRE QUEUE — HOW? IDK
//               // if this is a read, we check if the data being requested is write in MSHR, if it is, we can just fwd
//               // if it isn't, then we need to add to the queue as well
//               for (int i = 0; i < 16; i++) begin
//                 if (mshr_queue_full[pos][i].paddr == cur_addr && mshr_queue_full[pos][i].valid && mshr_queue_full[pos][i].we) begin
//                   // we have a write, we can simply forward this value!
//                   lsu_value_out_comb = mshr_queue_full[pos][i].data;
//                   needToAdd = 0;
//                   next_state = SEND_RESP_HC;
//                 end
//               end

//               if (needToAdd) begin
//                 // we weren't able to find any writes to the block, lets add a new queue entry
//                 mshr_entries[pos].valid = 1;
//                 mshr_entries[pos].paddr = cur_addr;
//                 mshr_entries[pos].we = lsu_we_in_reg;
//                 mshr_entries[pos].data = lsu_value_in_reg;
//                 mshr_entries[pos].tag = lsu_tag_in_reg;
//                 mshr_entries[pos].no_offset_addr = no_offset_addr;

//                 mshr_enqueue[pos] = 1;
//                 next_state = SEND_REQ_LC;
//               end
//             end

//           end else begin
//             // queue is full, cannot add, block request
//             // TODO: FIGURE OUT BLOCKING HERE
//             is_blocked_comb = 1;
//           end
//         end
//       end

//       CLEAR_MSHR: begin
//         $display("[%0t] Clearing MSHR", $time);

//         // TODO: need to dequeu MSHR and complete frfom front to bacl;
//         // for (int i = MSHR_COUNT - 1; i >= 0; i--) begin
//         //   // $display("The addr was %h and %h", lc_addr_in_reg[PADDR_BITS-1:BLOCK_OFFSET_BITS],
//         //   //          mshr_outputs[i].no_offset_addr);
//         //   if (mshr_outputs[i].no_offset_addr == lc_addr_in_reg[PADDR_BITS-1:BLOCK_OFFSET_BITS]) begin
//         //     $display("Found data %d", i);
//         //     found = 1;
//         //     pos   = i;
//         //   end
//         // end

//         for (int i = 0; i < MSHR_COUNT; i++) begin
//           $display("The addr was %h and %h", lc_addr_in_reg[PADDR_BITS-1:BLOCK_OFFSET_BITS],
//                    mshr_outputs[i].no_offset_addr);
//           if (mshr_outputs[i].no_offset_addr == lc_addr_in_reg[PADDR_BITS-1:BLOCK_OFFSET_BITS]) begin
//             found = 1;
//             pos   = i;
//           end
//         end

//         $display("Found %h something at loc %h", found, pos);
//         if (!mshr_empty[pos] && mshr_outputs[pos].valid && found) begin
//           mshr_dequeue[pos]  = 1;
//           // run the request
//           cache_hc_addr_next = mshr_outputs[pos].paddr;
//           lsu_tag_out_comb   = mshr_outputs[pos].tag;

//           $display("Running request for found mshr");

//           if (mshr_outputs[pos].we) begin
//             // this is a write 
//             cache_hc_valid_next = 1;
//             cache_hc_value_next = mshr_outputs[pos].data;
//             cache_hc_we_next = 1;
//             next_state = WRITE_FROM_MSHR;
//           end else begin
//             $display("read request for found mshr");
//             // this is A READ
//             next_state = READ_FROM_MSHR;
//           end
//         end else begin
//           next_state = IDLE;  // done doing all the stuff from MSHRs
//         end

//       end

//       WRITE_FROM_MSHR: begin
//         cache_hc_valid_next = 1;
//         cache_hc_we_next = 1;
//         // this should NEVER miss because the cache IS blcoking while unqueueing, everything SHOULD hit.
//         if (cache_hc_ready_out_reg) begin
//           // it took the signal, we can go to the next state, which is returning a signal that write completed, and then cominb back to finish the queue.
//           next_state = COMPLETE_WRITE;
//           cache_hc_valid_next = 0;
//         end
//       end

//       COMPLETE_WRITE: begin
//         lsu_valid_out_comb = 1;
//         lsu_write_complete_out_comb = 1;
//         // basically, wait until the LSU accepts that our write was done
//         if (lsu_ready_in_reg) begin
//           // LSU was ready, we can just submit the data and exit
//           next_state = CLEAR_MSHR;
//           cache_hc_valid_next = 0;
//           lsu_value_out_comb = 0;
//         end
//       end

//       READ_FROM_MSHR: begin
//         cache_hc_valid_next = 1;
//         cache_hc_addr_next  = cache_hc_addr_reg;
//         // this should NEVER miss because the cache IS blcoking while unqueueing, everything SHOULD hit.
//         if (cache_hc_ready_out_reg) begin
//           // it took the signal, we can go to the next state, which is returning a signal that read completed, and then cominb back to finish the queue.
//           next_state = COMPLETE_READ;
//           cache_hc_valid_next = 0;
//           lsu_value_out_comb = 0;
//         end
//       end

//       COMPLETE_READ: begin
//         lsu_valid_out_comb  = 1;
//         lsu_value_out_comb  = cache_hc_value_out_reg;
//         cache_hc_ready_next = 1;

//         // basically, wait until the LSU accepts that our write was done
//         if (lsu_ready_in_reg && cache_hc_valid_out_reg) begin
//           // LSU was ready, we can just submit the data and exit
//           next_state = CLEAR_MSHR;
//           cache_hc_valid_next = 0;
//         end
//       end

//       EVICT: begin
//         lc_valid_out_comb = 1;
//         lc_we_out_comb = 1;

//         if (lc_ready_in_reg) begin
//           // transcation done, we can go back to the clearing registers
//           next_state = CLEAR_MSHR;
//         end
//       end

//       SEND_REQ_LC: begin
//         lc_valid_out_comb = 1;
//         lc_addr_out_comb  = cache_lc_addr_out_reg;
//         if (lc_ready_in_reg) begin  // the LC took in the request, we are good
//           $display("req accepted to lc");
//           cache_hc_we_next = 0;
//           next_state = IDLE;
//         end
//       end

//       SEND_RESP_HC: begin
//         lsu_valid_out_comb = 1;
//         // Zero-pad the physical address to 64 bits
//         // The original code {{{64 - PADDR_BITS} {'b0}}, cache_hc_addr_out_reg} caused an error
//         // because the replication count was potentially unsized.
//         // Casting to 64' achieves the same zero-padding result more robustly.
//         lsu_addr_out_comb  = 64'(cache_hc_addr_out_reg);
//         lsu_value_out_comb = cache_hc_value_out_reg;
//         if (lsu_ready_in_reg) begin
//           next_state = IDLE;
//         end
//       end

//       default: begin
//         next_state = IDLE;
//       end
//     endcase

//     $monitor("[%0t][L1D] State was %d", $time, cur_state);
//   end

//   always_ff @(posedge clk_in) begin : l1_register_updates
//     if (!rst_N_in) begin
//       flush_in_reg <= 1'b1;  // flush when resetting
//       lsu_valid_in_reg <= 1'b0;
//       lsu_ready_in_reg <= 1'b0;
//       lsu_addr_in_reg <= '0;
//       lsu_value_in_reg <= '0;
//       lsu_tag_in_reg <= '0;
//       lsu_we_in_reg <= 1'b0;
//       lc_ready_in_reg <= 1'b0;
//       lc_valid_in_reg <= 1'b0;
//       lc_addr_in_reg <= '0;
//       lc_value_in_reg <= '0;

//       lsu_valid_out_reg <= 1'b0;
//       lsu_ready_out_reg <= 1'b0;
//       lsu_addr_out_reg <= '0;
//       lsu_value_out_reg <= '0;
//       lsu_write_complete_out_reg <= 1'b0;
//       lc_valid_out_reg <= 1'b0;
//       lc_ready_out_reg <= 1'b0;
//       lc_addr_out_reg <= '0;
//       lc_value_out_reg <= '0;
//       lc_we_out_reg <= 1'b0;
//       // pos_reg <= 0;
//     end else if (!cs_N_in) begin
//       if (next_state == IDLE) begin
//         flush_in_reg <= flush_in;
//         lsu_valid_in_reg <= lsu_valid_in;
//         lsu_addr_in_reg <= lsu_addr_in;
//         lsu_value_in_reg <= lsu_value_in;
//         lsu_tag_in_reg <= lsu_tag_in;
//         lsu_we_in_reg <= lsu_we_in;
//         lc_valid_in_reg <= lc_valid_in;
//         lc_addr_in_reg <= lc_addr_in;
//         lc_value_in_reg <= lc_value_in;

//         lsu_write_complete_out_reg <= lsu_write_complete_out;
//         lc_ready_out_reg <= lc_ready_out;
//         lsu_ready_out_reg <= lc_ready_out_comb;
//       end

//       lc_ready_in_reg <= lc_ready_in;
//       lc_ready_out_reg <= lc_ready_out_comb;
//       lc_addr_out_reg <= lc_addr_out_comb;
//       lc_valid_out_reg <= lc_valid_out_comb;
//       lc_we_out_reg <= lc_we_out_comb;
//       lsu_valid_out_reg <= lsu_valid_out_comb;
//       lsu_ready_out_reg <= lsu_ready_out_comb;
//       lsu_addr_out_reg <= lsu_addr_out_comb;
//       lsu_value_out_reg <= lsu_value_out_comb;
//       lc_value_out_reg <= lc_value_out_comb;
//       wait_reg <= wait_comb;

//       cur_state <= next_state;

//       lsu_ready_in_reg <= lsu_ready_in;
//       is_blocked_reg <= is_blocked_comb;

//       /* Update Cache Input States */
//       cache_flush_reg <= cache_flush_next;
//       cache_hc_valid_reg <= cache_hc_valid_next;
//       cache_hc_ready_reg <= cache_hc_ready_next;
//       cache_hc_addr_reg <= cache_hc_addr_next;
//       cache_hc_value_reg <= cache_hc_value_next;
//       cache_hc_we_reg <= cache_hc_we_next;
//       cache_cache_line_reg <= cache_cache_line_next;
//       cache_cl_reg <= cache_cl_next;
//       cache_lc_valid_in_reg <= cache_lc_valid_in_next;
//       cache_lc_ready_in_reg <= cache_lc_ready_in_next;
//       cache_lc_addr_in_reg <= cache_lc_addr_in_next;
//       cache_lc_value_in_reg <= cache_lc_value_in_next;
//       // pos_reg <= pos;
//       lsu_tag_out_reg <= lsu_tag_out_comb;
//     end
//   end

//   /* MSHR QUEUES */
//   typedef mshr_entry_t mshr_full_t[16-1:0];
//   mshr_full_t mshr_queue_full[MSHR_COUNT-1:0];

//   genvar i;
//   generate
//     for (i = 0; i < MSHR_COUNT; i++) begin : mshr_queues
//       mshr_queue #(
//           .QUEUE_SIZE(16),
//           .mem_request_t(mshr_entry_t)
//       ) mshr_queue_inst (
//           .clk_in(clk_in),
//           .rst_in(flush_in_reg),
//           .enqueue_in(mshr_enqueue[i]),
//           .dequeue_in(mshr_dequeue[i]),
//           .req_in(mshr_entries[i]),
//           .cycle_count(32'd0),  // dummy input, needs to be connected properly
//           .req_out(mshr_outputs[i]),
//           .empty(mshr_empty[i]),
//           .full(mshr_full[i]),
//           .queue_read_only(mshr_queue_full[i])
//       );
//     end
//   endgenerate


//   /* Generic Cache Storage  (This cache does NOT send an HC response upon LC response, L1D will need to handle that) */
//   // Define registers for inputs
//   logic cache_rst_N_reg;
//   logic cache_clk_reg;
//   logic cache_cs_reg;
//   logic cache_flush_reg;
//   logic cache_hc_valid_reg;
//   logic cache_hc_ready_reg;
//   logic [PADDR_BITS-1:0] cache_hc_addr_reg;
//   logic [64-1:0] cache_hc_value_reg;
//   logic cache_hc_we_reg;
//   logic [B*8-1:0] cache_cache_line_reg;
//   logic cache_cl_reg;
//   logic cache_lc_valid_in_reg;
//   logic cache_lc_ready_in_reg;
//   logic [PADDR_BITS-1:0] cache_lc_addr_in_reg;
//   logic [B*8-1:0] cache_lc_value_in_reg;

//   // Define registers for outputs
//   logic cache_lc_valid_out_reg;
//   logic cache_lc_ready_out_reg;
//   logic [PADDR_BITS-1:0] cache_lc_addr_out_reg;
//   logic [B*8-1:0] cache_lc_value_out_reg;
//   logic cache_we_out_reg;
//   logic cache_hc_valid_out_reg;
//   logic cache_hc_ready_out_reg;
//   logic cache_hc_we_out_reg;
//   logic [PADDR_BITS-1:0] cache_hc_addr_out_reg;
//   logic [64-1:0] cache_hc_value_out_reg;

//   // Define combinational signals for inputs
//   logic cache_flush_next;
//   logic cache_hc_valid_next;
//   logic cache_hc_ready_next;
//   logic [PADDR_BITS-1:0] cache_hc_addr_next;
//   logic [64-1:0] cache_hc_value_next;
//   logic cache_hc_we_next;
//   logic [B*8-1:0] cache_cache_line_next;
//   logic cache_cl_next;
//   logic cache_lc_valid_in_next;
//   logic cache_lc_ready_in_next;
//   logic [PADDR_BITS-1:0] cache_lc_addr_in_next;
//   logic [B*8-1:0] cache_lc_value_in_next;

//   cache #(
//       .A(A),
//       .B(B),
//       .C(C),
//       .W(64),
//       .ADDR_BITS(PADDR_BITS)
//   ) cache_module (
//       .rst_N_in(rst_N_in),
//       .clk_in(clk_in),
//       .cs_in(1),
//       .flush_in(flush_in_reg),
//       .hc_valid_in(cache_hc_valid_reg),
//       .hc_ready_in(cache_hc_ready_reg),
//       .hc_addr_in(cache_hc_addr_reg),
//       .hc_value_in(cache_hc_value_reg),
//       .hc_we_in(cache_hc_we_reg),
//       .cache_line_in(cache_cache_line_reg),
//       .cl_in(cache_cl_reg),
//       .lc_valid_out(cache_lc_valid_out_reg),
//       .lc_ready_out(cache_lc_ready_out_reg),
//       .lc_addr_out(cache_lc_addr_out_reg),
//       .lc_value_out(cache_lc_value_out_reg),
//       .we_out(cache_we_out_reg),
//       .lc_valid_in(cache_lc_valid_in_reg),
//       .lc_ready_in(cache_lc_ready_in_reg),
//       .lc_addr_in(cache_lc_addr_in_reg),
//       .lc_value_in(cache_lc_value_in_reg),
//       .hc_valid_out(cache_hc_valid_out_reg),
//       .hc_ready_out(cache_hc_ready_out_reg),
//       .hc_we_out(cache_hc_we_out_reg),
//       .hc_addr_out(cache_hc_addr_out_reg),
//       .hc_value_out(cache_hc_value_out_reg)
//   );

//   assign lsu_valid_out = lsu_valid_out_reg;
//   assign lsu_ready_out = lsu_ready_out_reg;
//   assign lsu_addr_out = lsu_addr_out_reg;
//   assign lsu_value_out = lsu_value_out_reg;
//   assign lsu_write_complete_out = lsu_write_complete_out_reg;
//   assign lc_valid_out = lc_valid_out_reg;
//   assign lc_ready_out = lc_ready_out_reg;
//   assign lc_addr_out = lc_addr_out_reg;
//   assign lc_value_out = lc_value_out_reg;
//   assign lc_we_out = lc_we_out_reg;
//   assign lsu_tag_out = lsu_tag_out_reg;


// endmodule : l1_data_cache