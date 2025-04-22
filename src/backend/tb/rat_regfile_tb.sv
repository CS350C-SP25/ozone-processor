`timescale 1ns/1ps

`include "../registers/reg_file.sv"
`include "../rat.sv"

typedef logic [31:0] uop_insn;   // Example: 32-bit micro-op instruction
typedef logic [63:0] rob_entry;  // Example: 64-bit ROB entry

module rat_regfile_tb;

  import reg_pkg::*;

  logic clk;
  logic rst;

  //==========================================================================
  // Signals for the register file
  //==========================================================================
  localparam int NUM_READ_PORTS  = 4;
  localparam int NUM_WRITE_PORTS = 2;

  // Read control signals (enable and index) and data outputs
  logic                read_en    [NUM_READ_PORTS];
  logic [$clog2(NUM_PHYS_REGS)-1:0] read_index [NUM_READ_PORTS];
  logic [WORD_SIZE-1:0] read_data  [NUM_READ_PORTS];

  // Write port signals using the struct defined in reg_pkg
  RegFileWritePort write_ports [NUM_WRITE_PORTS];

  //==========================================================================
  // Signals for the RAT module
  //==========================================================================
  // The RAT expects arrays for some inputs/outputs, as shown in its header.
  // uop_insn and rob_entry types are defined above if not already provided.
  uop_insn          instr [1:0];  // Instruction input array (2 elements)
  logic [63:0]      pc    [1:0];  // Program counters from instruction queue
  logic             ready_to_receive_more;
  rob_entry         rob_out [1:0];  // Output to ROB (2 elements)
  logic [1:0]       valid_output;
  logic             rob_stall;
  logic [1:0]       taken;          // From FRL; meaning used if reg valid is high
  // free_register is an array of 2 elements, each an index width of NUM_PHYS_REGS bits.
  logic [1:0][$clog2(NUM_PHYS_REGS)-1:0] free_register;
  logic             all_reg_full_stall;

  //==========================================================================
  // Instantiate the DUTs
  //==========================================================================

  // Instantiate the register file module.
  // This example uses separate arrays for read enable, read index, and read data.
  reg_file #(
      .NUM_READ_PORTS(NUM_READ_PORTS),
      .NUM_WRITE_PORTS(NUM_WRITE_PORTS)
  ) dut_reg_file (
      .clk(clk),
      .rst(rst),
      .read_en(read_en),
      .read_index(read_index),
      .read_data(read_data),
      .write_ports(write_ports)
  );

  // Instantiate the RAT module.
  rat #(
      .a(1)
  ) dut_rat (
      .clk(clk),
      .rst(rst),
      .instr(instr),
      .pc(pc),
      .ready_to_receive_more(ready_to_receive_more),
      .rob_out(rob_out),
      .valid_output(valid_output),
      .rob_stall(rob_stall),
      .taken(taken),
      .free_register(free_register),
      .all_reg_full_stall(all_reg_full_stall)
  );

  //==========================================================================
  // Clock Generation
  //==========================================================================
  // Create a 10 ns period clock (100 MHz).
  always #5 clk = ~clk;

  //==========================================================================
  // Stimulus
  //==========================================================================
  initial begin
    // Initial reset
    clk = 0;
    rst = 1;

    // Initialize register file read ports
    for (int i = 0; i < NUM_READ_PORTS; i++) begin
      read_en[i]    = 0;
      read_index[i] = 0;
    end

    // Initialize write port signals
    foreach (write_ports[i]) begin
      write_ports[i].en       = 0;
      write_ports[i].index_in = 0;
      write_ports[i].data_in  = '0;
    end

    // Initialize RAT signals
    for (int i = 0; i < 2; i++) begin
      instr[i] = '0;
      pc[i]    = 64'h0;
    end
    rob_stall             = 0;
    all_reg_full_stall    = 0;

    // Hold reset active for a few clock cycles.
    #20;
    rst = 0;

    // Example: Write a value to register 3 using write port 0 in the reg_file.
    write_ports[0].en       = 1;
    write_ports[0].index_in = 3;
    write_ports[0].data_in  = 64'hDEADBEEFDEADBEEF;
    #10;
    write_ports[0].en       = 0;

    // Example: Issue a read command on reg_file.
    read_en[0]    = 1;
    read_index[0] = 3;
    #10;
    $display("Read data from reg_file register 3: %h", read_data[0]);
    read_en[0]    = 0;

    // Provide a simple stimulus for RAT:
    // For instance, send an instruction and a PC value.
    instr[0] = 32'hdeadbeef;  
    pc[0]    = 64'h1000;
    // This example does not exercise full RAT functionality.
    // Additional stimulus should be added to test proper mapping/aliasing.

    #100;
    $finish;
  end

endmodule
