`include "../packages/reg_pkg.sv"

import reg_pkg::*;

module reg_file #(
    parameter WORD_SIZE       = reg_pkg::WORD_SIZE,
    parameter NUM_PHYS_REGS   = reg_pkg::NUM_PHYS_REGS,
    parameter int NUM_READ_PORTS  = 4,
    parameter int NUM_WRITE_PORTS = 8 // from FPU, ALU, BRU, LSU but only 2 will be written max at a time, intermmediate writing ports from r2
)(
    input  logic clk,
    input  logic rst,
    // Read control signals: an array of read enable signals
    input  logic [NUM_READ_PORTS-1:0] read_en,
    // Array of read index signals. Each element determines which register to read.
    input  logic [$clog2(NUM_PHYS_REGS)-1:0] read_index [NUM_READ_PORTS-1:0],
    // Read data outputs: an array to output the register contents
    output logic [WORD_SIZE-1:0] read_data [NUM_READ_PORTS-1:0],
    output logic [NUM_READ_PORTS*2-1:0] read_data_valid, // Whether its been updated or not
    // Write ports as defined in the package
    input  RegFileWritePort [NUM_WRITE_PORTS-1:0] write_ports,
    input NZCVWritePort nzcv_write_port // NZCV write port
);

    import reg_pkg::*;

    // Internal register file storage
    logic [WORD_SIZE-1:0] registers [NUM_PHYS_REGS-1:0];
    logic [NUM_PHYS_REGS-1:0] scoreboard; // Check if register is valid or not

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
                scoreboard[i] <= '0;
            end
        end else begin
            // For each write port, if enabled, perform the write operation.
            for (int i = 0; i < NUM_WRITE_PORTS; i++) begin
                if (write_ports[i].en) begin
                    registers[ write_ports[i].index_in ] <= write_ports[i].data_in;
                    scoreboard[ write_ports[i].index_in ] <= 1'b1; // Mark as valid
                end
            end
            if (nzcv_write_port.valid) begin
                // Write to NZCV register if valid
                registers[nzcv_write_port.index_in] <= nzcv_write_port.nzcv;
                scoreboard[nzcv_write_port.index_in] <= 1'b1; // Mark as valid
            end
        end
    end

endmodule

