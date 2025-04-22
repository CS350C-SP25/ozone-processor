`include "../reg_pkg.sv"

import reg_pkg::*;

module reg_file #(
    parameter WORD_SIZE       = reg_pkg::WORD_SIZE,
    parameter NUM_PHYS_REGS   = reg_pkg::NUM_PHYS_REGS,
    parameter int NUM_READ_PORTS  = 4,
    parameter int NUM_WRITE_PORTS = 2
)(
    input  logic clk,
    input  logic rst,
    // Read control signals: an array of read enable signals
    input  logic read_en [NUM_READ_PORTS],
    // Array of read index signals. Each element determines which register to read.
    input  logic [$clog2(NUM_PHYS_REGS)-1:0] read_index [NUM_READ_PORTS],
    // Read data outputs: an array to output the register contents
    output logic [WORD_SIZE-1:0] read_data [NUM_READ_PORTS],
    // Write ports as defined in the package
    input  RegFileWritePort write_ports [NUM_WRITE_PORTS]
);

    import reg_pkg::*;

    // Internal register file storage
    logic [WORD_SIZE-1:0] registers [NUM_PHYS_REGS-1:0];

    // Combinational read logic: for each read port, if read enabled, output the register data.
    always_comb begin
        for (int i = 0; i < NUM_READ_PORTS; i++) begin
            if (read_en[i]) begin
                read_data[i] = registers[ read_index[i] ];
            end else begin
                read_data[i] = '0;  // Default output when disabled (customize as needed)
            end
        end
    end

    // Synchronous logic for writing to registers and reset behavior.
    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset all registers to zero
            for (int i = 0; i < NUM_PHYS_REGS; i++) begin
                registers[i] <= '0;
            end
        end else begin
            // For each write port, if enabled, perform the write operation.
            for (int i = 0; i < NUM_WRITE_PORTS; i++) begin
                if (write_ports[i].en) begin
                    registers[ write_ports[i].index_in ] <= write_ports[i].data_in;
                end
            end
        end
    end

endmodule

