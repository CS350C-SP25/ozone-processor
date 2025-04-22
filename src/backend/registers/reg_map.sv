`include "../reg_pkg.sv"
import reg_pkg::*;

// used for the RAT + RRAT
// input arch register, output corresponding physical register
module reg_map #(
    parameter NUM_ARCH_REGS = reg_pkg::NUM_ARCH_REGS,
    parameter NUM_PHYS_REGS = reg_pkg::NUM_PHYS_REGS
)(
    input   logic                               clk,
    input   logic                               rst, // Set all mappings to default
    input   logic [1:0]                         commit_in, // Commit rename registers
    input   logic [1:0] [$clog2(NUM_ARCH_REGS)-1:0]   rename_arch_in, // Arch reg to map phys to
    input   logic [1:0] [$clog2(NUM_PHYS_REGS)-1:0]   rename_phys_in, // Phys reg to map to arch
    input   logic [3:0] [$clog2(NUM_ARCH_REGS)-1:0]   read_arch_in, // Arch reg to get mapping for
    output  logic [3:0] [$clog2(NUM_PHYS_REGS)-1:0]   phys_regs_out // Phys regs for arch regs
);
    logic [$clog2(NUM_PHYS_REGS)-1:0] register_mapping [NUM_ARCH_REGS-1:0];

    // Update mappings
    always_ff @(posedge clk) begin

        if (rst) begin
            // Default mapping. Map all to corresponding physical register
            for (int i = 0; i < NUM_ARCH_REGS; i++) begin
                register_mapping[i] <= i[$clog2(NUM_PHYS_REGS)-1:0]; // Only use bottom order bits of i
            end
        end else begin
            // Update mapping
            if (commit_in[1])
                register_mapping[rename_arch_in] <= rename_phys_in[1];
            if (commit_in[0])
                register_mapping[rename_arch_in] <= rename_phys_in[0];
        end

        // Read out mapping
        phys_regs_out <= {  
                            register_mapping[read_arch_in[3]],
                            register_mapping[read_arch_in[2]],
                            register_mapping[read_arch_in[1]],
                            register_mapping[read_arch_in[0]]
                        };
        
    end

endmodule
