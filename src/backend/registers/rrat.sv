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
    // rob_entry_valid is a bit vector indicating which entries are actual requests, or just empty for this clock cycle
    input [uop_pkg::INSTR_Q_WIDTH-1:0] rob_entry_valid,
    input rob_pkg::rob_entry [uop_pkg::INSTR_Q_WIDTH-1:0] rob_data,

    // FRL -- for freeing physical registers
    output logic [2*uop_pkg::INSTR_Q_WIDTH+1:0] free_registers_valid_out,
    output logic [2*uop_pkg::INSTR_Q_WIDTH+1:0][$clog2(NUM_PHYS_REGS) - 1:0] register_mappings
);

    // RRAT table: includes NZCV at index NUM_ARCH_REGS
    logic [$clog2(NUM_PHYS_REGS)-1:0] rrat_table [NUM_ARCH_REGS:0];
    uop_rr rr;
    uop_ri ri;
    int base;

    logic [$clog2(NUM_ARCH_REGS)-1:0] arch_dst;
    logic [$clog2(NUM_PHYS_REGS)-1:0] new_dest;
    logic [$clog2(NUM_PHYS_REGS)-1:0] old_dest;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i <= NUM_ARCH_REGS - 1; i++) begin
                rrat_table[i] <= i;  // 1-to-1 initial mapping
            end
            rrat_table[NUM_ARCH_REGS] <= NUM_ARCH_REGS; // NZCV
            free_registers_valid_out <= '0;
            register_mappings        <= '0;
        end else begin
            for (int i = 0; i < uop_pkg::INSTR_Q_WIDTH; i++) begin
                if (rob_entry_valid[i]) begin
                    logic set_nzcv;
                    // Update RRAT with latest committed physical mappings
                    // Update GPR mapping for both RR and RI formats
                    if (rob_data[i].uop.valb_sel) begin
                        // RR: two regsiter operands
                        get_data_rr(rob_data[i].uop.data, rr);
                        set_nzcv <= rr.set_nzcv;
                        /* first, check if any of the architectural registers are mapped differently. If they are,
                             we need to free the coresponding physical register before updating the mapping*/
                        arch_dst = rr.dst.gpr;
                        new_dest = rob_data[i].dest_reg_phys;
                        old_dest = rrat_table[arch_dst];

                        if (old_dest != new_dest) begin
                            // free the old destination register
                            free_registers_valid_out[2*i] <= 1'b1;
                            register_mappings[2*i] <= old_dest;
                        end

                        rrat_table[rr.dst.gpr] <= rob_data[i].dest_reg_phys;
                        rrat_table[rr.src1.gpr] <= rob_data[i].r1_reg_phys;
                        rrat_table[rr.src2.gpr] <= rob_data[i].r2_reg_phys;
                    end else begin
                        // ri
                        get_data_ri(rob_data[i].uop.data, ri);
                        set_nzcv <= ri.set_nzcv;

                        arch_dst = ri.dst.gpr;
                        new_dest = rob_data[i].dest_reg_phys;
                        old_dest = rrat_table[arch_dst];

                        if (old_dest != new_dest) begin
                            free_registers_valid_out[2*i+1]     <= 1'b1;
                            register_mappings[2*i+1]           <= old_dest;
                        end

                        rrat_table[ri.dst.gpr] <= rob_data[i].dest_reg_phys;
                        rrat_table[ri.src.gpr] <= rob_data[i].r1_reg_phys;
                    end
                    // Update NZCV mapping
                    rrat_table[NUM_ARCH_REGS] <= rob_data[i].nzcv_reg_phys;
                end
            end
        end
    end

endmodule
