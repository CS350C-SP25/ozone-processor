`include "../packages/rob_pkg.sv"

module rat #(
    parameter NUM_PHYS_REGS = reg_pkg::NUM_PHYS_REGS,
    parameter NUM_ARCH_REGS = reg_pkg::NUM_ARCH_REGS
) (
    input clk,
    input rst_N_in,

    // coming from instr queue, will need an adapter
    input logic q_valid,
    input uop_pkg::uop_insn [uop_pkg::INSTR_Q_WIDTH-1:0] instr,
    output logic q_increment_ready,

    // output to rob
    output rob_pkg::rob_entry [uop_pkg::INSTR_Q_WIDTH-1:0] rob_data,
    output logic rob_data_valid,
    input logic rob_ready,

    // from FRL
    output logic [2*uop_pkg::INSTR_Q_WIDTH+1:0] frl_ready,  // we consumed the values (6 per cycle)
    input logic [2*uop_pkg::INSTR_Q_WIDTH+1:0][$clog2(NUM_PHYS_REGS) - 1:0] free_register_data,
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

        if (instr[i].valb_sel) begin  // valb is a register
          get_data_rr(instr[i].data, regs_rr_in[i]);

          if (!reg_valid[regs_rr_in[i].src1.gpr] || !reg_valid[regs_rr_in[i].src2.gpr]) begin
            $display("UH OH THIS REG DOESNT HAVE ANYTHING VALID IN IT; basically NOBODYS USED IT YET");
          end

          dst  = regs_rr_in[i].dst;
          src1 = regs_rr_in[i].src1;
          src2 = regs_rr_in[i].src2;

          regFileOut[i].index_in <= free_register_data[2+i];
          regFileOut[i].en       <= 1;
          regFileOut[i].data_in  <= 64'(regs_ri_in[i].imm);
        end else begin  // we have an intermediate
          get_data_ri(instr[i].data, regs_ri_in[i]);

          if (!reg_valid[regs_ri_in[i].src.gpr]) begin
            $display("UH OH THIS REG DOESNT HAVE ANYTHING VALID IN IT; basically NOBODYS USED IT YET");
          end

          dst  = regs_ri_in[i].dst;
          src1 = regs_ri_in[i].src;
          src2 = free_register_data[2+i];  // intermediate phys reg

          regFileOut[i].index_in <= 0;
          regFileOut[i].en       <= 0;
          regFileOut[i].data_in  <= 0;
        end

        // Mark FRL consumption
        frl_ready[i]     <= making_progress;                        // dst reg used
        frl_ready[2+i]   <= making_progress && !instr[i].valb_sel; // intermediate only if RI
        frl_ready[4+i]   <= making_progress;                        // NZCV reg always used

        // Write ROB entry
        outputs[i].pc            <= instr[i].pc;
        outputs[i].next_pc       <= (instr[i].uopcode == UOP_BL || instr[i].uopcode == UOP_BCOND) && 
                                    instr[i].data.predict_taken ? instr[i].data.branch_target : 
                                    instr[i].pc + 4;
        outputs[i].uop           <= instr[i];
        outputs[i].r1_reg_phys   <= store[src1];
        outputs[i].r2_reg_phys   <= store[src2];
        outputs[i].dest_reg_phys <= free_register_data[i];
        outputs[i].status        <= ISSUED;

        if (making_progress) begin
          reg_valid[dst.gpr] <= 1;
          store[dst.gpr]     <= free_register_data[i];

          // Allocate and map NZCV
          reg_valid[NUM_ARCH_REGS] <= 1;
          store[NUM_ARCH_REGS]     <= free_register_data[2*uop_pkg::INSTR_Q_WIDTH+i];
        end
      end
    end
  end
endmodule
