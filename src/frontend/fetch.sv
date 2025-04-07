import uop_pkg::*;
import op_pkg::*;

// fetch logic unit frfr
// we will generate multiple of these in our top level module to simulate the multiple instn fetch
// one module of this will only fetch one instruction at a time
module fetch #(
    parameter INSTRUCTION_WIDTH = op_pkg::INSTRUCTION_WIDTH,
    parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH,
    parameter CACHE_LINE_WIDTH = 64, // TODO: waiting for the l1 i$ to be added to change this
) (
    // general control signals
    input logic clk_in,                              // clock signal
    input logic rst_in,                              // reset signal
    input logic flush_in,                            // TODO: need or no? 
    output logic fetch_valid,                        // valid when done
    // pipeline data signals
    input logic [63:0] program_counter,              // PC from PC register, cant lie just guessing this is coming correctly to me from top level module
    output uop_ri [INSTRUCTION_WIDTH-1:0] ri,        // raw instruction to send to decode
);



endmodule