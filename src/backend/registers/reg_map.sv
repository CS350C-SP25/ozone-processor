`include "../rob_pkg.sv"
import rob_pkg::*;

// used for the RAT + RRAT
// input arch register, output corresponding physical register
module reg_map #(
    parameter NUM_ARCH_REGS = rob_pkg::NUM_ARCH_REGS,
    parameter NUM_PHYS_REGS = rob_pkg::NUM_PHYS_REGS
)(
    input   logic                               clk,
    input   logic                               rst,
    input   logic                               valid_in, // We are committing
    input   logic [$clog2(NUM_ARCH_REGS)-1:0] [$clog2(NUM_PHYS_REGS)-1:0]   rename_in,
    output  logic [$clog2(NUM_ARCH_REGS)-1:0] [$clog2(NUM_PHYS_REGS)-1:0]   phys_regs_out
);
    logic [$clog2(NUM_PHYS_REGS)-1:0] register_mapping [NUM_ARCH_REGS-1:0];

    // Update mappings
    always_ff @(posedge clk) begin

        if (rst) begin
            // Default mapping. Map all to corresponding physical register
            for (int i = 0; i < NUM_ARCH_REGS; i++) begin
                register_mapping[i] <= i[$clog2(NUM_PHYS_REGS)-1:0]; // Only use bottom order bits of iterator
            end
        end else begin
            // Update mapping
            if (commit_valid) begin
                for (int i = 0; i < NUM_ARCH_REGS; i++) begin
                    if (rename_mask_in[i] == 1'b1)
                        register_mapping[i] <= phys_reg_in;
                end
            end
        end
    end

    // Read out all physical registers
    assign phys_reg_out = register_mapping[arch_reg_in];

endmodule