`timescale 1ns / 1ps

`include "../frontend/frontend.sv"
`include "../backend/backend.sv"
`include "../ozone.sv"
`include "../util/uop_pkg.sv"
`include "../util/instr-queue.sv"

module ozone_tb;

localparam CACHE_LINE_BYTES   = 64; // 64 bytes = 512 bits
localparam CACHE_LINE_WIDTH   = CACHE_LINE_BYTES; 
localparam MEM_SIZE = 4096; // 4KB

// DUT Signals
logic clk_in;
logic rst_N;
logic cs_N_in;
logic start;
logic [63:0] start_pc;
logic lc_ready_in;
logic lc_valid_in;
logic [63:0] lc_addr_in; // address to get from lc
logic [511:0] lc_value_in; // entire cacheline
logic lc_valid_out;
logic lc_ready_out;
logic [63:0] lc_addr_out;
logic [511:0] lc_value_out;
logic lc_we_out;

// Instantiate the DUT (entire ozone processor)
ozone dut {
    .clk_in         (clk_in),
    .rst_N          (rst_N),
    .cs_N_in        (cs_N_in),
    .start          (start),
    .start_pc       (start_pc),
    .lc_ready_in    (lc_ready_in),
    .lc_valid_in    (lc_valid_in),
    .lc_addr_in     (lc_addr_in),
    .lc_value_in    (lc_value_in),
    .lc_valid_out   (lc_valid_out),
    .lc_ready_out   (lc_ready_out),
    .lc_addr_out    (lc_addr_out),
    .lc_value_out   (lc_value_out),
    .lc_we_out      (lc_we_out)
};

// Clock Generation
localparam CLK_PERIOD = 10; // in ns
initial begin
    clk_in = 0;
    forever #(CLK_PERIOD / 2) clk_in = ~clk_in;
end

// Reset Generation and Initialization
initial begin
    rst_N = 1'b0;
    cs_N_in = 1'b1;
    start = 1b'0;
    start_pc = '0;
    lc_ready_in = 1'b0;
    lc_valid_in = 1'b0;
    lc_addr_in = '0;
    lc_value_in = '0;
    #(CLK_PERIOD * 5); // Holding reset for 5 clock cycles
    rst_N = 1'b1;
    cs_N_in = 1'b1; // TODO: Do we even need chip select?, keeping it off for now
    #(CLK_PERIOD)
end

// Helper Task to "Cheat" In Data to L1d and L1i to kickstart processor
task initialize_caches (input logic lc_ready_out, input logic lc_valid_in, 
                        input logic [63:0] lc_addr_in, input logic [511:0] lc_value_in);
    @(posedge clk);
    

endtask

// Stimulus and Checking
initial begin
    // Wait for reset signal

    // Test Case 1: MOVZ to ADD
    // Write in data
    
    

end


endmodule