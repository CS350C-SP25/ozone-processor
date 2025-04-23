`include "../packages/rob_pkg.sv"

// ASSUME implementing w/

module rat #(
    parameter NUM_PHYS_REGS = reg_pkg::NUM_PHYS_REGS,
    parameter NUM_ARCH_REGS = reg_pkg::NUM_ARCH_REGS
) (
    input clk,
    input rst_N_in,


    // coming from instr queue, will need an adapter
    input logic q_valid,
    input uop_pkg::uop_insn [1:0] instr,
    output logic q_increment_ready,

    // output to rob
    output rob_pkg::rob_entry [1:0] rob_data,
    output logic rob_data_valid,
    input logic rob_ready,

    // from FRL
    output logic [3:0] frl_ready,  // we consumed the values
    input logic [3:0][$clog2(NUM_PHYS_REGS) - 1:0] free_register_data,
    input logic frl_valid,  // all regs are full already, just wait it out

    // for intermediate writing
    output reg_pkg::RegFileWritePort [1:0] regfile
);
  import rob_pkg::*;
  import uop_pkg::*;

  logic making_progress;
  assign making_progress = q_valid && frl_valid && rob_ready;
  logic [$clog2(NUM_ARCH_REGS) - 1:0][$clog2(NUM_PHYS_REGS) - 1:0] store;
  logic [NUM_ARCH_REGS  - 1:0] reg_valid;  // for debugging

  rob_entry [1:0] outputs;
  assign rob_data = outputs;
  uop_rr regs_rr_in[1:0];
  uop_ri regs_ri_in[1:0];

  reg_pkg::RegFileWritePort [1:0] regFileOut;
  assign regfile = regFileOut;

  always_ff @(posedge clk) begin
    if (!rst_N_in) begin
      reg_valid <= 0;
    end else begin
      rob_data_valid <= making_progress;
      q_increment_ready <= making_progress;

      for (int i = 0; i < 2; i++) begin
 

        uop_reg dst;
        uop_reg src1;
        uop_reg src2;
        if (instr[i].valb_sel) begin  // valb is a register
          get_data_rr(instr[i].data, regs_rr_in[i]);

          // for debugging
          if (!reg_valid[regs_rr_in[i].src1.gpr] || !reg_valid[regs_rr_in[i].src1.gpr]) begin
            $display(
                "UH OH THIS REG DOESNT HAVE ANYTHING VALID IN IT; basically NOBODYS USED IT YET");
          end

          dst  = regs_rr_in[i].dst;
          src1 = regs_rr_in[i].src1;
          src2 = regs_rr_in[i].src2;

          // regFileOut[i] <= reg_pkg::RegFileWritePort'{index_in: 0, en: 0, data_in: 0};
        end else begin  // we have an intermediate
          get_data_ri(instr[i].data, regs_ri_in[i]);

          // for debugging
          if (!reg_valid[regs_ri_in[i].src.gpr]) begin
            $display(
                "UH OH THIS REG DOESNT HAVE ANYTHING VALID IN IT; basically NOBODYS USED IT YET");
          end

          dst  = regs_ri_in[i].dst;
          src1 = regs_ri_in[i].src;
          src2 = free_register_data[2+i];

          // regFileOut[i] <= reg_pkg::RegFileWritePort'{
              // index_in: free_register_data[2+i],
              // en: 1,
              // data_in: 64'(regs_ri_in[i].imm)
          // };
        end
        frl_ready[i] <= making_progress;  // reg i is always used up, since we always have a dst
        frl_ready[2+i] <= making_progress && !instr[i].valb_sel; // if intermediate, we mark the 2+i reg is as used too

        // outputs[i] <= rob_entry'{
            // pc: instr[i].pc,
            // next_pc: instr[i].pc,  // TODO: WHAT
            // uop: instr[i],
            // r1_reg_phys: store[src1],
            // r2_reg_phys: store[src2],
            // dest_reg_phys: free_register_data[i],
            // status: ISSUED
        // };
        if (making_progress) begin
          reg_valid[dst.gpr] <= 1;  // for debug
          store[dst.gpr] <= free_register_data[i];
        end
      end
    end
  end
endmodule
