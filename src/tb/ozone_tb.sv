`timescale 1ns / 1ps

`include "../frontend/frontend.sv"
`include "../backend/backend.sv"
`include "../ozone.sv"
`include "../util/op_pkg.sv"
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
ozone dut (
    .clk_in         (clk_in),
    .rst_N          (rst_N),
    .cs_N_in        (cs_N_in),
    .start          (start),
    .start_pc       (start_pc),
    .lc_ready_in    (lc_ready_out), // populating l1i w this
    .lc_valid_in    (lc_valid_out), // populating l1i w this
    .lc_addr_in     (lc_addr_out), // populating l1i w this
    .lc_value_in    (lc_value_out), // populating l1i w this
    .lc_valid_out   (lc_valid_in),
    .lc_ready_out   (lc_ready_in), 
    .lc_addr_out    (lc_addr_in), 
    .lc_value_out   (lc_value_in), 
    .lc_we_out      (lc_we_out) // can ignore this
);

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
    start = 1'b0;
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

// Stimulus and Checking
initial begin
    // Wait for reset signal
    wait (rst_N_in == 1'b1);
    @(posedge clk_in);

    $display("Starting test sequence at time %ot", $time);

    // Test Case 1: Simple ALU operation
    $display("Test Case 1: Simple ADDS");
        lc_value_out[31:0] = {OPCODE_MOVZ, 2'b00, 16'hFFFF, 5'b00000}; // movz x0, #0xffff
        lc_value_out[63:32] = {OPCODE_MOVZ, 2'b01, 16'hFFFF, 5'b00001}; // movz x1, #0xffff, lsl 16
        lc_value_out[95:64] = {OPCODE_MOVZ, 2'b11, 16'hFFFF, 5'b00010}; // movz x2, #0xffff, lsl 32
        lc_value_out[127:96] = {OPCODE_MOVZ, 2'b10, 16'hFFFF, 5'b00011}; // movz x3, #0xffff, lsl 48
        lc_value_out[159:128] = {OPCODE_MOVZ, 2'b00, 16'h0001, 5'b00100}; // movz x4, #1
        lc_value_out[191:160] = {OPCODE_ADDS, 5'b00001, 6'b000000, 5'b00000, 5'b00101}; // adds x5, x0, x1
        lc_value_out[223:192] = {OPCODE_ADDS, 5'b00011, 6'b000000, 5'b00010, 5'b00110}; // adds x6, x2, x3
        lc_value_out[255:224] = {OPCODE_ADDS, 5'b00101, 6'b000000, 5'b00110, 5'b00111}; // adds x7, x5, x6
        lc_value_out[287:256] = {OPCODE_ADDS, 5'b00111, 6'b000000, 5'b00100, 5'b01000}; // adds x8, x4, x7
        lc_value_out[319:288] = {OPCODE_HLT, 21'0}; // halt bc end of program
        lc_addr_out = 64'b0; // start at addr 0x0000_0000_0000_0000
        start_pc = 64'b0;
        // signal to start populating l1i
        lc_valid_out = 1'b1;
        start = 1'b1;
        
        #(CLK_PERIOD * 10) // have quite a bit of delay for our l1i to get data right

        // check at cycle 7 which instrns are at which stage of pipeline
        







end


endmodule