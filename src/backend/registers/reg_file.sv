`include "../reg_pkg.sv"
`include "../rob_pkg.sv"

import rob_pkg::*;
import reg_pkg::*;


module reg_file #(
    parameter WORD_SIZE = rob_pkg::WORD_SIZE, // Width of each register
    parameter NUM_PHYS_REGS = rob_pkg::NUM_PHYS_REGS,
    parameter int NUM_READ_PORTS = 4,
    parameter int NUM_WRITE_PORTS = 2
)(
    input  logic                                        clk,
    input  logic                                        rst,
    // These are packed structs that contain all necessary signals for making reads and writes
    inout  RegFileReadPort                              read_ports [NUM_READS_P],
    input  RegFileWritePort                             write_ports[NUM_WRITES_P]
    
);
    logic [WORD_SIZE-1:0] registers [NUM_PHYS_REGS-1:0];

    // Assumptions for reads and writes:
    // 1) There will be NO siultaneous writes to the same physical register
    // 2) 
    
    always_ff @(posedge clk) begin

        if (rst) begin // Zero out all registers
            for (int i = 0; i < NUM_PHYS_REGS; i++)
                registers[i] <= '0;
        end else if (we) begin // Write
            for (int i = 0; i < NUM_PHYS_REGS; i++) begin
                if (data_mask_in[i] == '1)
                    registers[i] <= data_in[i];
            end
        end
    end
    
    assign data_out = registers[index_in];
endmodule