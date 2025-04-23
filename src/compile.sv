`include "./backend/rat.sv"

module a (
    // Define ports here if needed
);

    rat #(
        .NUM_PHYS_REGS     (reg_pkg::NUM_PHYS_REGS),
        .NUM_ARCH_REGS     (reg_pkg::NUM_ARCH_REGS)
    ) u_rat (
        // Clock & Reset
        .clk               (clk),
        .rst               (rst),

        // Instruction Queue Interface (adapter needed)
        .q_valid           (q_valid),
        .instr             (instr),
        .q_increment_ready (q_increment_ready),

        // Output to ROB (Reorder Buffer)
        .rob_data          (rob_data),
        .rob_data_valid    (rob_data_valid),
        .rob_ready         (rob_ready),

        // Free Register List (FRL) Interface
        .frl_ready         (frl_ready),
        .free_register_data(free_register_data),
        .frl_valid         (frl_valid),

        // Register File Interface (intermediate writing)
        .regfile           (regfile)
    );

endmodule
