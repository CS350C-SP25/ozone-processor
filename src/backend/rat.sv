`include "./rob_pkg.sv"

import rob_pkg::*;

package renaming;

endpackage
// ASSUME implementing w/

module rat #(
    parameter a = 1
) (
    input clk,
    input rst,


    // coming from instr queue, will need an adapter
    input uop_insn [1:0] instr,
    input logic [63:0][1:0] pc,
    output logic ready_to_receive_more,

    // output to rob
    output rob_entry [1:0] rob_out,
    output logic [1:0] valid_output,
    input logic rob_stall,

    // from FRL
    output logic [1:0] taken,  // does not have any meaning if reg == false
    input logic [1:0][$clog2(NUM_PHYS_REGS) - 1:0] free_register,
    input logic all_reg_full_stall,  // all regs are full already, just wait it out
);

  logic [$clog2(NUM_ARCH_REGS) - 1:0][$clog2(NUM_PHYS_REGS) - 1:0] store;
  logic [$clog2(NUM_ARCH_REGS) - 1:0] reg_valid;  // for debugging

  rob_entry [1:0] outputs;
  assign rob_out = outputs;

  always_ff @(posedge clk) begin
    if (!rst) begin
      reg_valid <= 0;
    end else begin

      if (instr[0].valb_sel) begin
        uop_rr regs_in;
        get_data_rr(instr[0].data, regs_in);

        //regs.dst.gpr;
        //regs.src1.gpr;
        //regs.src2.gpr;

        // for debugging
        if (!reg_valid[regs_in.src1.gpr] || !reg_valid[regs_in.src1.gpr]) begin
          $display(
              "UH OH THIS REG DOESNT HAVE ANYTHING VALID IN IT; basically NOBODYS USED IT YET");
        end

        outputs[0].r1_reg_phys   <= store[regs_in.src1.gpr];
        outputs[0].r2_reg_phys   <= store[regs_in.src2.gpr];
        outputs[0].dest_reg_phys <= store[regs_in.src2.gpr];
      end
    end
  end
endmodule


