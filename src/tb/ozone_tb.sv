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

// LC signals for instruction cache (L1I)
logic l1i_lc_ready_in;
logic l1i_lc_valid_in;
logic [63:0] l1i_lc_addr_in;
logic [511:0] l1i_lc_value_in;

// LC signals for data cache (L1D)
logic l1d_lc_ready_in;
logic l1d_lc_valid_in;
logic [63:0] l1d_lc_addr_in;
logic [511:0] l1d_lc_value_in;

// --- Emulated LC Outputs (for feeding DUT) ---
logic lc_valid_out;
logic lc_ready_out;
logic [63:0] lc_addr_out;
logic [511:0] lc_value_out;
logic lc_we_out;

// Instantiate the DUT (ozone processor)
ozone dut (
    .clk_in(clk_in),
    .rst_N_in(rst_N),
    .cs_N_in(cs_N_in),
    .start(start),
    .start_pc(start_pc),

    // L1I <-> LLC interface
    .l1i_lc_ready_in(lc_ready_out),
    .l1i_lc_valid_in(lc_valid_out),
    .l1i_lc_addr_in(lc_addr_out),
    .l1i_lc_value_in(lc_value_out),

    // L1D <-> LLC interface
    .l1d_lc_ready_in(1'b0), // No L1D traffic in this test
    .l1d_lc_valid_in(1'b0),
    .l1d_lc_addr_in(64'b0),
    .l1d_lc_value_in(512'b0)
);

// Clock Generation
localparam CLK_PERIOD = 10; // 10 ns clock
initial begin
    clk_in = 0;
    forever #(CLK_PERIOD/2) clk_in = ~clk_in;
end

// Reset Generation and Initialization
initial begin
    rst_N = 1'b0;
    cs_N_in = 1'b1;
    start = 1'b0;
    start_pc = '0;
    lc_ready_out = 1'b0;
    lc_valid_out = 1'b0;
    lc_addr_out = '0;
    lc_value_out = '0;
    #(CLK_PERIOD * 5);
    rst_N = 1'b1;
    #(CLK_PERIOD);
end

// Stimulus and Checking
initial begin
    // Wait until reset is deasserted
    wait (rst_N == 1'b1);
    @(posedge clk_in);

    $display("Starting test sequence at time %0t", $time);

    // === Program: Load Instructions into Cache Line ===
    $display("Loading instructions into emulated LC...");

    // Program: simple ALU operations
    lc_value_out[31:0]   = {OPCODE_MOVZ, 2'b00, 16'hFFFF, 5'b00000}; // movz x0, #0xffff
    lc_value_out[63:32]  = {OPCODE_MOVZ, 2'b01, 16'hFFFF, 5'b00001}; // movz x1, #0xffff, lsl 16
    lc_value_out[95:64]  = {OPCODE_MOVZ, 2'b11, 16'hFFFF, 5'b00010}; // movz x2, #0xffff, lsl 32
    lc_value_out[127:96] = {OPCODE_MOVZ, 2'b10, 16'hFFFF, 5'b00011}; // movz x3, #0xffff, lsl 48
    lc_value_out[159:128] = {OPCODE_MOVZ, 2'b00, 16'h0001, 5'b00100}; // movz x4, #1
    lc_value_out[191:160] = {OPCODE_ADDS, 5'b00001, 6'b000000, 5'b00000, 5'b00101}; // adds x5, x0, x1
    lc_value_out[223:192] = {OPCODE_ADDS, 5'b00011, 6'b000000, 5'b00010, 5'b00110}; // adds x6, x2, x3
    lc_value_out[255:224] = {OPCODE_ADDS, 5'b00101, 6'b000000, 5'b00110, 5'b00111}; // adds x7, x5, x6
    lc_value_out[287:256] = {OPCODE_ADDS, 5'b00111, 6'b000000, 5'b00100, 5'b01000}; // adds x8, x4, x7
    lc_value_out[319:288] = {OPCODE_HLT, 21'b0}; // halt

    lc_addr_out = 64'b0; // starting address
    lc_valid_out = 1'b1;
    start_pc = 64'b0;

    @(posedge clk_in);
    lc_valid_out = 1'b0; // stop driving after one cycle
    start = 1'b1;
    @(posedge clk_in);
    start = 1'b0;

    #(CLK_PERIOD * 50); // allow some cycles for execution

    $display("Finished Test Case 1 at time %0t", $time);

    // Test Case 2: bcond
    $display("Test Case 2: Simple Branching");
        // start
        lc_value_out[31:0] = 32'h200080D2; // movz x0, #1
        lv_value_out[63:0] = 32'h410080D2; // movz x1, #2
        lc_value_out[95:64] = 32'h030001EB; // subs x3, x0, x1
        lc_value_out[127:96] = 32'hA1090054; // b.ne .notequal
        // .goback
        lc_value_out[159:128] = 32'hA50005CA; // eor 	x5, x5, x5
        lc_value_out[191:160] = 32'hE50325AA; // mvn 	x5, x5
        lc_value_out[223:192] = 32'hA00000F8; // stur	x0, [x5]
        lc_value_out[255:224] = {OPCODE_HLT, 21'b0}; // halt
        // .notequal
        lc_value_out[287:256] = 32'h00340091; // add x0, x0, #13
        lc_value_out[319:288] = 32'h00300091; // add x0, x0, #12
        lc_value_out[351:320] = 32'h16000014; // b .goback

    lc_addr_out = 64'b0;
    lv_valid_out = 1'b1;
    start_pc = 64'b0;

    @(posedge clk_in);
    lc_valid_out = 1'b0; // stop driving after one cycle
    start = 1'b1;
    @(posedge clk_in);
    start = 1'b0;

    #(CLK_PERIOD * 50); // allow some cycles for execution

    $display("Finished Test Case 2 at time %0t", $time);

end 
    $finish;


endmodule
