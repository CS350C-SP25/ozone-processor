`include "../packages/rob_pkg.sv"
`include "../packages/reg_pkg.sv"
`include "../../util/uop_pkg.sv"

import uop_pkg::*;
import reg_pkg::*;
import rob_pkg::*;

module rrat #(
    parameter NUM_PHYS_REGS = reg_pkg::NUM_PHYS_REGS,
    parameter NUM_ARCH_REGS = reg_pkg::NUM_ARCH_REGS
) (
    input clk,
    input rst,

    // from reorder buffer
    input [uop_pkg::INSTR_Q_WIDTH-1:0] rob_entry_valid,
    input rob_pkg::rob_entry [uop_pkg::INSTR_Q_WIDTH-1:0] rob_data,

    // FRL -- for freeing physical registers
    output logic [2*uop_pkg::INSTR_Q_WIDTH+1:0] free_registers_valid_out,
    output logic [2*uop_pkg::INSTR_Q_WIDTH+1:0][$clog2(NUM_PHYS_REGS) - 1:0] register_mappings
);

    // RRAT table: includes NZCV at index NUM_ARCH_REGS
    logic [$clog2(NUM_PHYS_REGS)-1:0] rrat_table [NUM_ARCH_REGS:0];
    uop_rr rr;
    int base;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i <= NUM_ARCH_REGS; i++) begin
                rrat_table[i] <= i;  // 1-to-1 initial mapping
            end
            free_registers_valid_out <= '0;
            register_mappings        <= '0;
        end else begin
            for (int i = 0; i < uop_pkg::INSTR_Q_WIDTH; i++) begin
                if (rob_entry_valid[i]) begin
                    get_data_rr(rob_data[i].uop.data, rr);

                    // Update RRAT with latest committed physical mappings
                    rrat_table[rr.dst.gpr]       <= rob_data[i].dest_reg_phys;
                    rrat_table[rr.src1.gpr]      <= rob_data[i].r1_reg_phys;
                    rrat_table[rr.src2.gpr]      <= rob_data[i].r2_reg_phys;
                    rrat_table[NUM_ARCH_REGS]    <= rob_data[i].nzcv_reg_phys;

                    // Mark physical registers as free
                    base = i * 3;
                    free_registers_valid_out[base + 0] <= 1;
                    free_registers_valid_out[base + 1] <= 1;
                    free_registers_valid_out[base + 2] <= 1;

                    register_mappings[base + 0] <= rob_data[i].r1_reg_phys;
                    register_mappings[base + 1] <= rob_data[i].r2_reg_phys;
                    register_mappings[base + 2] <= rob_data[i].nzcv_reg_phys;
                end
            end
        end
    end

endmodule
