`include "../packages/rob_pkg.sv"
`ifndef RAT_SV
`define RAT_SV
import rob_pkg::*;
import reg_pkg::*;
import uop_pkg::*;

module rat #(
    parameter NUM_PHYS_REGS = reg_pkg::NUM_PHYS_REGS,
    parameter NUM_ARCH_REGS = reg_pkg::NUM_ARCH_REGS
) (
    input clk,
    input rst_N_in,

    // coming from instr queue, will need an adapter
    input logic q_valid,
    input uop_pkg::instr_queue_t instr,
    output logic q_increment_ready,

    // output to rob
    output rob_pkg::rob_entry [uop_pkg::INSTR_Q_WIDTH-1:0] rob_data,
    output logic rob_data_valid,
    input logic rob_ready,

    // from FRL
    output logic [3*uop_pkg::INSTR_Q_WIDTH-1:0] frl_ready,  // we consumed the values (6 per cycle)
    input logic [3*uop_pkg::INSTR_Q_WIDTH-1:0][$clog2(NUM_PHYS_REGS) - 1:0] free_register_data,
    input logic frl_valid,  // all regs are full already, just wait it out
    // for intermediate writing
    output reg_pkg::RegFileWritePort [uop_pkg::INSTR_Q_WIDTH-1:0] regfile
);
  import rob_pkg::*;
  import uop_pkg::*;

  logic making_progress;
  assign making_progress = q_valid && frl_valid && rob_ready;

  // [NUM_ARCH_REGS] used for NZCV
  logic [NUM_ARCH_REGS:0][$clog2(NUM_PHYS_REGS) - 1:0] store;
  logic [NUM_ARCH_REGS:0] reg_valid;

  rob_entry [uop_pkg::INSTR_Q_WIDTH-1:0] outputs;
  assign rob_data = outputs;

  uop_rr regs_rr_in[uop_pkg::INSTR_Q_WIDTH-1:0];
  uop_ri regs_ri_in[uop_pkg::INSTR_Q_WIDTH-1:0];

  reg_pkg::RegFileWritePort [uop_pkg::INSTR_Q_WIDTH-1:0] regFileOut;
  assign regfile = regFileOut;

  always_ff @(posedge clk) begin
    if (!rst_N_in) begin
      reg_valid <= 0;
    end else begin
      rob_data_valid <= making_progress;
      q_increment_ready <= making_progress;

      for (int i = 0; i < uop_pkg::INSTR_Q_WIDTH; i++) begin
        uop_reg dst;
        uop_reg src1;
        uop_reg src2;
        logic   set_nzcv;

        get_data_rr(instr[i].data, regs_rr_in[i]);
        get_data_ri(instr[i].data, regs_ri_in[i]);

        if (instr[i].valb_sel) begin  // valb is a register
          if (!reg_valid[regs_rr_in[i].src1.gpr] || !reg_valid[regs_rr_in[i].src2.gpr]) begin
            $display(
                "UH OH THIS REG DOESNT HAVE ANYTHING VALID IN IT; basically NOBODYS USED IT YET");
          end

          dst = regs_rr_in[i].dst;
          src1 = regs_rr_in[i].src1;
          src2 = regs_rr_in[i].src2;
          set_nzcv = regs_rr_in[i].set_nzcv;

          regFileOut[i].index_in <= 0;
          regFileOut[i].en       <= 0;
          regFileOut[i].data_in  <= 0;
          if (is_xzr(regs_rr_in[i].src1)) begin
            regFileOut[i].index_in <= free_register_data[2+i];
            regFileOut[i].en       <= 1;
            regFileOut[i].data_in  <= 0;
            // TODO
          end
          if (is_xzr(regs_rr_in[i].src2)) begin
            // TODO 
          end
        end else if (instr[i].uopcode != UOP_HLT) begin  // we have an intermediate
          get_data_ri(instr[i].data, regs_ri_in[i]);

          if (!reg_valid[regs_ri_in[i].src.gpr]) begin
            $display(
                "UH OH THIS REG DOESNT HAVE ANYTHING VALID IN IT; basically NOBODYS USED IT YET");
          end

          dst = regs_ri_in[i].dst;
          src1 = regs_ri_in[i].src;
          set_nzcv = regs_ri_in[i].set_nzcv;
          src2 = free_register_data[2+i];  // intermediate phys reg
          $display("Allocated %0d->%0d %0d->%0d %0d for RRI uopcode 0x%0h", dst,
                   free_register_data[i], src1, store[src1], src2, instr[i].uopcode);
          regFileOut[i].index_in <= free_register_data[2+i];
          regFileOut[i].en       <= 1;
          regFileOut[i].data_in  <= 64'(regs_ri_in[i].imm);
        end

        // Mark FRL consumption
        frl_ready[0*uop_pkg::INSTR_Q_WIDTH+i] <= making_progress;  // dst reg used
        frl_ready[1*uop_pkg::INSTR_Q_WIDTH+i]   <= making_progress && !instr[i].valb_sel; // intermediate only if RI
        frl_ready[2*uop_pkg::INSTR_Q_WIDTH+i] <= set_nzcv;  // if nzcv reg used

        // Write ROB entry
        outputs[i].pc <= instr[i].pc;
        outputs[i].next_pc       <= (instr[i].uopcode == UOP_BL || instr[i].uopcode == UOP_BCOND) && 
                                    instr[i].data.predict_taken ? instr[i].data.branch_target : 
                                    instr[i].pc + 4;
        outputs[i].uop <= instr[i];
        outputs[i].r1_reg_phys <= store[src1];
        outputs[i].r2_reg_phys <= store[src2];
        outputs[i].dest_reg_phys <= free_register_data[0*uop_pkg::INSTR_Q_WIDTH+i];
        outputs[i].nzcv_reg_phys <= set_nzcv ? free_register_data[2*uop_pkg::INSTR_Q_WIDTH+i] : store[NUM_ARCH_REGS];
        outputs[i].status <= READY;

        if (making_progress) begin
          reg_valid[dst.gpr]       <= 1;
          store[dst.gpr]           <= free_register_data[i];

          // Allocate and map NZCV
          reg_valid[NUM_ARCH_REGS] <= 1;
          if (set_nzcv) store[NUM_ARCH_REGS] <= free_register_data[2*uop_pkg::INSTR_Q_WIDTH+i];
        end
      end
    end
  end
endmodule
`endif  // RAT_SV
