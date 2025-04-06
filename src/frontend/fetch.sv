import uop_pkg::*;
import op_pkg::*;

// fetch logic unit frfr
module fetch #(
    parameter INSTRUCTION_WIDTH = op_pkg::INSTRUCTION_WIDTH,
    parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH,
    parameter CACHE_LINE_WIDTH = 64, // TODO: waiting for the l1 i$ to be added to change this
) (
    // general control signals
    input logic clk_in,                              // clock signal
    input logic rst_in,                              // reset signal
    input logic flush_in,                            // i dont think fetch needs this tbh, would assume the flush signal is just for instruction queue on decode's end
    // pipeline control signals
    output logic fetch_valid,                        // valid when done
    // pipeline data signals
    input logic [63:0] program_counter,              // PC from PC register
    output uop_ri [INSTRUCTION_WIDTH-1:0] ri,        // raw instruction to send to decode
);

endmodule