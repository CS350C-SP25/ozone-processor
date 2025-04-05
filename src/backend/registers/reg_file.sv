import rob_pkg::*;

module reg_file #(
    parameter WORD_SIZE = rob_pkg::WORD_SIZE, // Width of each register
    parameter NUM_PHYS_REGS = rob_pkg::NUM_PHYS_REGS
)(
    input   logic                                       clk,
    input   logic                                       rst,
    input   logic                                       we, // Write enable
    input   logic [$clog2(NUM_PHYS_REGS)-1:0]           index_in, // TODO: May change later to some param for index size
    input   logic [NUM_PHYS_REGS-1:0] [WORD_SIZE-1:0]   data_in, // 2D word array to write
    input   logic [NUM_PHYS_REGS-1:0]                   data_mask_in, // Mask indicating valid words to write
    output  logic [WORD_SIZE-1:0]                       data_out
);
    logic [WORD_SIZE-1:0] registers [NUM_PHYS_REGS-1:0];
    
    always_ff @(posedge clk ) begin

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