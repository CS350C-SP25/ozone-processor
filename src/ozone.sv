`include "./backend/backend.sv"
`include "./frontend/frontend.sv"

module ozone (
    input logic clk_in,
    input logic rst_N_in,
    input logic start,
    input logic [63:0] start_pc,
    // more inputs from "lc" to frontend
);
    frontend #() fe (
        .clk_in(),
        .rst_N_in(),
        .cs_N_in(),
        .start(),
        .start_pc(),
        .x_bcond_resolved(),
        .x_pc_incorrect(),
        .x_taken(),
        .x_pc(),
        .x_correction_offset(),
        .lc_ready_in(),
        .lc_valid_in(),
        .lc_addr_in(),
        .lc_value_in(),
        .exe_ready(),
        .lc_valid_out(),
        .lc_ready_out(),
        .lc_addr_out(),
        .lc_value_out(),
        .lc_we_out(),
        .instruction_queue_pushes(),
        .instruction_queue_in()
    );

    backend be (
        .clk_in(),
        .rst_N_in(),
        .instr_queue(),
        .bcond_resolved_out(),
        .pc_incorrect_out(),  // this means that the PC that we had originally predicted was incorrect. We need to fix.
        .taken_out(),  // if the branch resolved as taken or not -- to update PHT and GHR
        .pc_out(), // pc that is currently in the exec phase (the one that just was resolved)
        .correction_offset_out() // the offset of the correction from x_pc (could change this to be just the actual correct PC instead ??)
    );

endmodule
