`include "./backend/rat.sv"

module compile (
    // Define ports here if needed
     input clk,
    input rst,


    // coming from instr queue, will need an adapter
    input logic q_valid,
    input uop_pkg::uop_insn [0:0] instr,
    output logic q_increment_ready,

    // output to rob
    output rob_pkg::rob_entry [0:0] rob_data,
    output logic rob_data_valid,
    input logic rob_ready,

    // from FRL
    output logic [0:0] frl_ready,  // we consumed the values
    input logic [0:0][0:0] free_register_data,
    input logic frl_valid,  // all regs are full already, just wait it out

    // for intermediate writing
    output reg_pkg::RegFileWritePort [1:0] regfile

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
