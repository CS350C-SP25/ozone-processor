`include "./rob_pkg.sv"
`include "./reg_pkg.sv"

module rrat #(
    parameter NUM_PHYS_REGS = reg_pkg::NUM_PHYS_REGS,
    parameter NUM_ARCH_REGS = reg_pkg::NUM_ARCH_REGS
) (
    input clk,
    input rst,

    // from reorder buffer
    input [1:0] rob_entry_valid,
    input rob_pkg::rob_entry [1:0] rob_data,

    // FRL -- for freeing physical regsiters
    output logic [5:0] free_registers_valid_out,
    output logic [5:0] [$clog2(NUM_PHYS_REGS) - 1:0] register_mappings
);
    // the retirement RAT: arch_reg->phys_reg
    logic [$clog2(NUM_PHYS_REGS)-1:0] rrat_table [NUM_ARCH_REGS-1:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            // on reset, map arch->phys one‑to‑one
            for (int i = 0; i < NUM_ARCH_REGS; i++) begin
                rrat_table[i] <= i;
                free_registers_valid_out <= '0;
                register_mappings       <= '0;
            end 
        end else begin
            for (int i = 0; i < 2; i++) begin
                if (rob_entry_valid[i]) begin
                    // save the arch_reg->phys_reg mapping
                    uop_rr rr;
                    get_data_rr(rob_data[i].data, rr);

                    rrat_table[rr.dst.gpr] <= rob_data[i].dest_reg_phys;
                    rrat_table[rr.src1.gpr] <= rob_data[i].r1_reg_phys;
                    rrat_table[rr.src2.gpr] <= rob_data[i].r2_reg_phys;

                    // send requests to free the physical registers
                    // if i = 0, sets indices 0-2. If i = 1, sets indices 3-5
                    free_registers_valid_out[i*3] <= '1;
                    free_registers_valid_out[i*3 + 1] <= '1;
                    free_registers_valid_out[i*3 + 2] <= '1;

                    // send a request to the FRL to free
                    register_mappings[i*3] <= rob_data[i].r1_reg_phys;
                    register_mappings[i*3] <= rob_data[i].r2_reg_phys;
                    register_mappings[i*3] <= rob_data[i].dest_reg_phys;
                end
                // else, don't do anything. We won't always get 2 instructions to commit each clock cycle. Or 1
            end
        end
    end

endmodule