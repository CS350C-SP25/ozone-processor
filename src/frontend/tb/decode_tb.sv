`timescale 1ns/1ps
`include "../decode.sv"
// Assuming you have these package files defined elsewhere
import op_pkg::*;
import uop_pkg::*;

module decode_tb;
  // Parameters - using the same as in your module
  parameter INSTRUCTION_WIDTH = op_pkg::INSTRUCTION_WIDTH;
  parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH;
  parameter INSTR_Q_DEPTH = uop_pkg::INSTR_Q_DEPTH;
  parameter INSTR_Q_WIDTH = uop_pkg::INSTR_Q_WIDTH;
  
  // Inputs
  logic clk_in;
  logic rst_N_in;
  logic flush_in;
  instruction_array fetched_ops;
  branch_data_array branch_data;
  logic [63:0] pc;
  logic fetch_valid;
  logic exe_ready;
  
  // Outputs
  logic decode_ready;
  uop_insn instruction_queue_in[INSTR_Q_WIDTH-1:0];
  
  // Instantiate the decode module
  decode #(
    .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH),
    .SUPER_SCALAR_WIDTH(SUPER_SCALAR_WIDTH),
    .INSTR_Q_DEPTH(INSTR_Q_DEPTH),
    .INSTR_Q_WIDTH(INSTR_Q_WIDTH)
  ) dut (
    .clk_in(clk_in),
    .rst_N_in(rst_N_in),
    .flush_in(flush_in),
    .fetched_ops(fetched_ops),
    .branch_data(branch_data),
    .pc(pc),
    .fetch_valid(fetch_valid),
    .exe_ready(exe_ready),
    .decode_ready(decode_ready),
    .instruction_queue_in(instruction_queue_in)
  );
  
  // Clock generation
  always #5 clk_in = ~clk_in;
  
  // ADDS x0, x0, x1 instruction encoding
  // 32-bit ARM instruction: 0x8b010000 (in little-endian format)
  // Breaking down the instruction:
  // - SF=1 (64-bit operation)
  // - op=0 (ADD)
  // - S=1 (sets flags)
  // - Rm=0001 (x1)
  // - option/shift=000000
  // - Rn=00000 (x0)
  // - Rd=00000 (x0)
  
  // Test procedure
  initial begin
    $dumpfile("decode_tb.vcd");  // Name of the VCD file
    $dumpvars(0, decode_tb);     // Dump all variables in the testbench
    // Initialize signals
    clk_in = 0;
    rst_N_in = 0;
    flush_in = 0;
    fetch_valid = 1;
    pc = 64'h1000; // Some arbitrary PC value
    
    // Initialize fetched_ops with zeros
    for (int i = 0; i < SUPER_SCALAR_WIDTH; i++) begin
      fetched_ops[i] = 0;
    end
    
    // Initialize branch_data (ignored for now)
    // Assuming it's an array matching SUPER_SCALAR_WIDTH
    
    // Apply reset
    #20;
    rst_N_in = 1;
    #20;
    
    // Set up ADDS x0, x0, x1 instruction (0x8b010000)
    fetched_ops[0] = 32'hab010000;
    fetch_valid = 1;
    exe_ready = 1; // Always true as specified
    $display(decode_ready);
    // Wait for decode_ready and then print output
    @(posedge decode_ready);
    
    // Print the uopcodes when decode_ready is set
    $display("Decode Ready: %b", decode_ready);
    for (int i = 0; i < INSTR_Q_WIDTH; i++) begin
        $display("Instruction Queue[%0d] uopcode: %x", i, instruction_queue_in[i].uopcode);
        $display("Instruction Queue[%0d] details:", i);
        $display("  PC: 0x%h", instruction_queue_in[i].pc);
        $display("  valb_sel: %b", instruction_queue_in[i].valb_sel);
        $display("  mem_read: %b", instruction_queue_in[i].mem_read);
        $display("  mem_write: %b", instruction_queue_in[i].mem_write);
        $display("  w_enable: %b", instruction_queue_in[i].w_enable);
        $display("  valid: %b", instruction_queue_in[i].valid);
    end
    
    // Run for a bit longer to observe behavior
    #50;
    
    // End simulation
    $finish;
  end
  
  // Optional: Monitor signals for debugging
  
  
endmodule