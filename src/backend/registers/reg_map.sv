`include "../rob_pkg.sv"

// used for the RAT + RRAT
// input arch register, output corresponding physical register
module reg_map #(
    parameter NUM_ARCH_REGS = rob_pkg::NUM_ARCH_REGS,
    parameter NUM_PHYS_REGS = rob_pkg::NUM_PHYS_REGS
)(
    input   logic                               clk,
    input   logic                               rst, // Set all mappings to default
    input   logic [1:0]                         valid_in, // Commits rename_in registers
    input   logic [1:0] [$clog2(NUM_PHYS_REGS)-1:0]   rename_in,
    output  logic [1:0] [$clog2(NUM_PHYS_REGS)-1:0]   phys_regs_out
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
            if (valid_in[1])
                register_mapping[rename_in[1]] <= rename_in[1];
            if (valid_in[0])
                register_mapping[rename_in[0]] <= rename_in[0];
        end

        // Read out mapping
        phys_regs_out <= {register_mapping[rename_in[1]], register_mapping[rename_in[0]]}
    end

endmodule