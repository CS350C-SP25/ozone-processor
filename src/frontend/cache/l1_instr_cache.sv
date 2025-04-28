// `include "../../../mem/src/cache.sv"

// just needs to wrap the generic cache and block when missed
module l1_instr_cache #(
    parameter int A = 4,
    parameter int B = 64,
    parameter int C = 1536,
    parameter int PADDR_BITS = 64
) (
    // Inputs from l0
    input logic clk_in,
    input logic rst_N_in,
    input logic cs_N_in,
    input logic flush_in,

    input logic l0_valid_in,
    input logic l0_ready_in,
    input logic [63:0] l0_addr_in,


    // signals that go to l0
    output logic l0_valid_out,
    output logic l0_ready_out,
    output logic [63:0] l0_addr_out,
    output logic [511:0] l0_value_out,


    // Inputs from LLC
    input logic lc_ready_in,
    input logic lc_valid_in,
    input logic [PADDR_BITS-1:0] lc_addr_in,
    input logic [8*B-1:0] lc_value_in,

    // signals that go to LLC
    output logic lc_valid_out,
    output logic lc_ready_out,
    output logic [PADDR_BITS-1:0] lc_addr_out,
    output logic [8*B-1:0] lc_value_out,
    output logic lc_we_out
);

  typedef enum logic [2:0] {
    IDLE,
    SEND_REQ_LC,
    SEND_RESP_HC,
    IN_FLIGHT,  // blocking state
    WAIT_CACHE,  // waiting for cache req to resolve
    REQ_CACHE,  // sending req to cache
    WRITE_CACHE,
    READ_CACHE
  } states;

  states cur_state, next_state;

  reg flush_in_reg;
  reg l0_valid_in_reg;
  reg l0_ready_in_reg;
  reg [63:0] l0_addr_in_reg;
  reg l0_we_in_reg;
  reg lc_ready_in_reg;
  reg lc_valid_in_reg;
  reg [PADDR_BITS-1:0] lc_addr_in_reg;
  reg [8*B-1:0] lc_value_in_reg;

  reg l0_valid_out_reg;
  reg l0_ready_out_reg;
  reg [63:0] l0_addr_out_reg;
  reg [8*B-1:0] l0_value_out_reg;
  reg l0_write_complete_out_reg;
  reg lc_valid_out_reg;
  reg lc_ready_out_reg;
  reg [PADDR_BITS-1:0] lc_addr_out_reg;
  reg [8*B-1:0] lc_value_out_reg;
  reg lc_we_out_reg;

  reg is_blocked_reg;

  logic l0_valid_out_comb;
  logic l0_ready_out_comb;
  logic [63:0] l0_addr_out_comb;
  logic [8*B-1:0] l0_value_out_comb;
  logic l0_write_complete_out_comb;
  logic lc_valid_out_comb;
  logic lc_ready_out_comb;
  logic [PADDR_BITS-1:0] lc_addr_out_comb;
  logic [8*B-1:0] lc_value_out_comb;
  logic lc_we_out_comb;

  localparam int BLOCK_OFFSET_BITS = $clog2(B);
  logic [PADDR_BITS-1:0] cur_addr;
  logic [PADDR_BITS-1:BLOCK_OFFSET_BITS] no_offset_addr;

  assign cur_addr = l0_addr_in_reg[PADDR_BITS-1:0];
  assign no_offset_addr = l0_addr_in_reg[PADDR_BITS-1:BLOCK_OFFSET_BITS];

  always_comb begin : l1d_combinational_logic
    l0_valid_out_comb = '0;
    l0_ready_out_comb = 1'b0;
    l0_addr_out_comb = l0_addr_out_reg;
    l0_value_out_comb = l0_value_out_reg;
    l0_write_complete_out_comb = 1'b0;
    lc_valid_out_comb = 1'b0;
    lc_ready_out_comb = 1'b0;
    lc_addr_out_comb = lc_addr_out_reg;
    lc_value_out_comb = lc_value_out_reg;
    lc_we_out_comb = 1'b0;
    next_state = cur_state;

    /* Cache Inputs */
    cache_flush_next = 0;
    cache_hc_valid_next = 0;
    cache_hc_ready_next = 0;
    cache_hc_addr_next = cache_hc_addr_reg;
    cache_hc_value_next = '0;
    cache_hc_we_next = l0_we_in_reg;
    cache_cl_next = 0;
    cache_lc_valid_in_next = 0;
    cache_lc_ready_in_next = 0;
    cache_lc_addr_in_next = lc_addr_in_reg;
    cache_lc_value_in_next = lc_value_in_reg;

    case (cur_state)
      IDLE: begin
        if (lc_valid_in_reg) begin
          lc_ready_out_comb = 1;
        end else if (l0_valid_in_reg) begin
          l0_ready_out_comb = 1;
        end
        // $display("[Time %0t] lc_valid_in_reg=%0b | l0_ready_out_comb=%0b | l0_valid_in_reg=%0b | (triggered action)", 
        //  $time, lc_valid_in_reg, l0_ready_out_comb, l0_valid_in_reg);
        if (lc_valid_in_reg || (l0_ready_out_comb && l0_valid_in_reg)) begin // if data from lc or if l0 is reading
          next_state = (lc_valid_in_reg) ? WRITE_CACHE : READ_CACHE;
        end
      end

      WAIT_CACHE: begin
        cache_hc_valid_next = 0;
        cache_lc_valid_in_next = 0;

        // if this was a write from lower cache, we can just write
        if (lc_valid_in_reg) begin
                    $display("lc_valid_in true...write from lower cache possible ()");

          next_state = SEND_RESP_HC;
        end else if (cache_lc_valid_out_reg) begin  // we missed, we need to req data
          $display("miss detected on read...requesting data from lower cache ");

          // Requesting data from lower cache -- this is a MISS
          cache_lc_ready_in_next = 1;  // complete transcation
          next_state = SEND_REQ_LC;  // just request data now
        end else if (cache_hc_valid_out_reg) begin
          // READ HIT! We can move to sending data back to the top
                    $display("read hit");

          cache_hc_ready_next = 1;  // complete transcation
          l0_value_out_comb = cache_hc_value_out_reg;
          next_state = SEND_RESP_HC;
        end
      end

      READ_CACHE: begin
        $display("ATTEMPTING TO READ CACHE DATA");
        cache_hc_addr_next = cur_addr;
        cache_hc_valid_next = 1;

        next_state = (cache_hc_ready_out_reg) ? WAIT_CACHE : cur_state;
      end

      WRITE_CACHE: begin
        $display("[L1i] WRITING FROM LC");
        cache_lc_valid_in_next = (cache_hc_ready_out_reg || cache_lc_ready_out_reg) ? 0 : 1;
        cache_lc_value_in_next = lc_value_in_reg;
        cache_lc_addr_in_next = lc_addr_in_reg;
        next_state = (cache_hc_ready_out_reg || cache_lc_ready_out_reg) ? WAIT_CACHE : cur_state;
      end

      SEND_REQ_LC: begin
        lc_valid_out_comb = 1;
        lc_addr_out_comb  = cache_lc_addr_out_reg;
        $display("sending request to LC");
        if (lc_ready_in_reg) begin  // the LC took in the request, we are good
          $display("req accepted to lc...");
          $display("[%0t][LC] %s request sent: Addr = 0x%h", 
         $time, (lc_we_out_comb ? "Write" : "Read"), cache_lc_addr_out_reg);
          cache_hc_we_next = 0;
          next_state = IDLE;
        end
      end

      SEND_RESP_HC: begin
        l0_valid_out_comb = 1;
        // Zero-pad the physical address to 64 bits
        // The original code {{{64 - PADDR_BITS} {'b0}}, cache_hc_addr_out_reg} caused an error
        // because the replication count was potentially unsized.
        // Casting to 64' achieves the same zero-padding result more robustly.
        l0_addr_out_comb  = 64'(cache_hc_addr_out_reg);
        l0_value_out_comb = cache_hc_value_out_reg;
                  $display("[Time %0t][L1] Sending data to L0 | Addr: 0x%h | Value (first 8B): %h %h %h %h %h %h %h %h", 
                 $time, 
                 l0_addr_out_comb, 
                 l0_value_out_comb[7:0], 
                 l0_value_out_comb[15:8], 
                 l0_value_out_comb[23:16], 
                 l0_value_out_comb[31:24], 
                 l0_value_out_comb[39:32], 
                 l0_value_out_comb[47:40], 
                 l0_value_out_comb[55:48], 
                 l0_value_out_comb[63:56]);
        if (l0_ready_in_reg) begin
                    // cache_hc_ready_next = 1; 


          next_state = IDLE;
        end
      end

      default: begin
        next_state = IDLE;
      end
    endcase

    $monitor("[%0t][L1i] State was %d", $time, cur_state);
  end

  always_ff @(posedge clk_in) begin : l1_register_updates
    if (!rst_N_in) begin
      flush_in_reg <= 1'b1;  // flush when resetting
      l0_valid_in_reg <= 1'b0;
      l0_ready_in_reg <= 1'b0;
      l0_addr_in_reg <= '0;
      l0_we_in_reg <= 1'b0;
      lc_ready_in_reg <= 1'b0;
      lc_valid_in_reg <= 1'b0;
      lc_addr_in_reg <= '0;
      lc_value_in_reg <= '0;

      l0_valid_out_reg <= 1'b0;
      l0_ready_out_reg <= 1'b0;
      l0_addr_out_reg <= '0;
      l0_value_out_reg <= '0;
      l0_write_complete_out_reg <= 1'b0;
      lc_valid_out_reg <= 1'b0;
      lc_ready_out_reg <= 1'b0;
      lc_addr_out_reg <= '0;
      lc_value_out_reg <= '0;
      lc_we_out_reg <= 1'b0;
      // pos_reg <= 0;
    end else if (!cs_N_in) begin
      if (next_state == IDLE) begin
        flush_in_reg <= flush_in;
        l0_valid_in_reg <= l0_valid_in;
        l0_addr_in_reg <= l0_addr_in;
        lc_valid_in_reg <= lc_valid_in;
        if (lc_valid_in_reg) begin
    $display("\n====================L1 DATA==============================");
    $display("[Time %0t][L1 Cache] Data came in from LC!", $time);
    $display("    Incoming Address (lc_addr_in_reg): 0x%h", lc_addr_in_reg);
    $display("    Incoming Data (lc_value_in_reg):  0x%h", lc_value_in_reg);
    $display("    Current State: %s", 
        (cur_state == IDLE)         ? "IDLE" :
        (cur_state == SEND_REQ_LC)  ? "SEND_REQ_LC" :
        (cur_state == SEND_RESP_HC) ? "SEND_RESP_HC" :
        (cur_state == IN_FLIGHT)    ? "IN_FLIGHT" :
        (cur_state == WAIT_CACHE)   ? "WAIT_CACHE" :
        (cur_state == REQ_CACHE)    ? "REQ_CACHE" :
        (cur_state == WRITE_CACHE)  ? "WRITE_CACHE" :
        (cur_state == READ_CACHE)   ? "READ_CACHE" :
        "UNKNOWN"
    );
    $display("==================================================");
end
        lc_addr_in_reg <= lc_addr_in;
        lc_value_in_reg <= lc_value_in;

        lc_ready_out_reg <= lc_ready_out;
        l0_ready_out_reg <= lc_ready_out_comb;
      end

      lc_ready_in_reg <= lc_ready_in;
      lc_ready_out_reg <= lc_ready_out_comb;
      lc_addr_out_reg <= lc_addr_out_comb;
      lc_valid_out_reg <= lc_valid_out_comb;
      lc_we_out_reg <= lc_we_out_comb;
      l0_valid_out_reg <= l0_valid_out_comb;
      l0_ready_out_reg <= l0_ready_out_comb;
      l0_addr_out_reg <= l0_addr_out_comb;
      l0_value_out_reg <= l0_value_out_comb;
      lc_value_out_reg <= lc_value_out_comb;

      cur_state <= next_state;

      l0_ready_in_reg <= l0_ready_in;

      /* Update Cache Input States */
      cache_flush_reg <= cache_flush_next;
      cache_hc_valid_reg <= cache_hc_valid_next;
      cache_hc_ready_reg <= cache_hc_ready_next;
      cache_hc_addr_reg <= cache_hc_addr_next;
      cache_hc_value_reg <= cache_hc_value_next;
      cache_hc_we_reg <= cache_hc_we_next;
      cache_cache_line_reg <= cache_cache_line_next;
      cache_cl_reg <= cache_cl_next;
      cache_lc_valid_in_reg <= cache_lc_valid_in_next;
      cache_lc_ready_in_reg <= cache_lc_ready_in_next;
      cache_lc_addr_in_reg <= cache_lc_addr_in_next;
      cache_lc_value_in_reg <= cache_lc_value_in_next;
      // pos_reg <= pos;
    end
  end

  /* Generic Cache Storage  (This cache does NOT send an HC response upon LC response, L1D will need to handle that) */
  // Define registers for inputs
  logic cache_rst_N_reg;
  logic cache_clk_reg;
  logic cache_cs_reg;
  logic cache_flush_reg;
  logic cache_hc_valid_reg;
  logic cache_hc_ready_reg;
  logic [PADDR_BITS-1:0] cache_hc_addr_reg;
  logic [512-1:0] cache_hc_value_reg;
  logic cache_hc_we_reg;
  logic [B*8-1:0] cache_cache_line_reg;
  logic cache_cl_reg;
  logic cache_lc_valid_in_reg;
  logic cache_lc_ready_in_reg;
  logic [PADDR_BITS-1:0] cache_lc_addr_in_reg;
  logic [B*8-1:0] cache_lc_value_in_reg;

  // Define registers for outputs
  logic cache_lc_valid_out_reg;
  logic cache_lc_ready_out_reg;
  logic [PADDR_BITS-1:0] cache_lc_addr_out_reg;
  logic [B*8-1:0] cache_lc_value_out_reg;
  logic cache_we_out_reg;
  logic cache_hc_valid_out_reg;
  logic cache_hc_ready_out_reg;
  logic cache_hc_we_out_reg;
  logic [PADDR_BITS-1:0] cache_hc_addr_out_reg;
  logic [511:0] cache_hc_value_out_reg;

  // Define combinational signals for inputs
  logic cache_flush_next;
  logic cache_hc_valid_next;
  logic cache_hc_ready_next;
  logic [PADDR_BITS-1:0] cache_hc_addr_next;
  logic [511:0] cache_hc_value_next;
  logic cache_hc_we_next;
  logic [B*8-1:0] cache_cache_line_next;
  logic cache_cl_next;
  logic cache_lc_valid_in_next;
  logic cache_lc_ready_in_next;
  logic [PADDR_BITS-1:0] cache_lc_addr_in_next;
  logic [B*8-1:0] cache_lc_value_in_next;

  cache #(
      .A(A),
      .B(B),
      .C(C),
      .W(512),
      .ADDR_BITS(PADDR_BITS)
  ) cache_module (
      .rst_N_in(rst_N_in),
      .clk_in(clk_in),
      .cs_in(1),
      .flush_in(flush_in_reg),

          // Inputs from higher-level cache
          //basically that it wants a request done
          //this is us (l1)
      .hc_valid_in(cache_hc_valid_reg),
      .hc_ready_in(cache_hc_ready_reg),
      .hc_addr_in(cache_hc_addr_reg),
      .hc_value_in('0),
      .hc_we_in('0),
      .cache_line_in('0),
      .cl_in('0),
      .lc_valid_out(cache_lc_valid_out_reg),
      .lc_ready_out(cache_lc_ready_out_reg),
      .lc_addr_out(cache_lc_addr_out_reg),
      .lc_value_out(cache_lc_value_out_reg),
      .we_out(cache_we_out_reg),
      .lc_valid_in(cache_lc_valid_in_reg),
      .lc_ready_in(cache_lc_ready_in_reg),
      .lc_addr_in(cache_lc_addr_in_reg),
      .lc_value_in(cache_lc_value_in_reg),
      .hc_valid_out(cache_hc_valid_out_reg),
      .hc_ready_out(cache_hc_ready_out_reg),
      .hc_we_out(cache_hc_we_out_reg),
      .hc_addr_out(cache_hc_addr_out_reg),
      .hc_value_out(cache_hc_value_out_reg)
  );

  assign l0_valid_out = l0_valid_out_reg;
  assign l0_ready_out = l0_ready_out_reg;
  assign l0_addr_out = l0_addr_out_reg;
  assign l0_value_out = l0_value_out_reg;
  assign lc_valid_out = lc_valid_out_reg;
  assign lc_ready_out = lc_ready_out_reg;
  assign lc_addr_out = lc_addr_out_reg;
  assign lc_value_out = lc_value_out_reg;
  assign lc_we_out = lc_we_out_reg;


endmodule : l1_instr_cache