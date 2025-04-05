import rob_pkg::*;

module reg_file #(
    parameter WORD_SIZE = rob_pkg::WORD_SIZE, // Width of each register
    parameter NUM_PHYS_REGS = rob_pkg::NUM_PHYS_REGS
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    we, // Write enable
    input  logic [$clog2(NUM_PHYS_REGS)-1:0]   index_in, // TODO: May change later to some param for index size
    input  logic [WORD_SIZE-1:0]    data_in, // Data in for writing only
    output logic [WORD_SIZE-1:0]    data_out
);
    logic [WORD_SIZE-1:0] registers [NUM_PHYS_REGS-1:0];
    
    always_ff @(posedge clk ) begin

        if (rst) begin // Zero out all registers
            for (int i = 0; i < NUM_PHYS_REGS; i++)
                registers[i] <= '0;
        end else if (we) // Write
            registers[index_in] <= data_in;
    end
    
    assign data_out = registers[index_in];
endmodule