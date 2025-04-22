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

// TODO: implement this
// priority encoder w/ a NUM_PHYS_REG array vs a stack/queue w/ NUM_PHYS_REG * $clog2(NUM_PHYS_REG) array as implementation
module frl #(
) (
    input clk,
    input rst,

    // consumer - RAT
    input logic [1:0] taken,  // does not have any meaning if reg == false
    output logic [1:0][$clog2(NUM_PHYS_REGS) - 1:0] register,
    output logic stall,  // all regs are full already, just wait it out
    // technically we could make this granular, but tbh stalling if we only have one dest reg is fine for simplicity

    // connect to RRAT to free evicted entries (WAR/WAW)
    input logic [1:0] valid,
    input logic [1:0][$clog2(NUM_PHYS_REGS) - 1:0] freeing_registers

    // 
);

  logic [NUM_PHYS_REGS - 1 : 0] in_use;
  logic [$clog2(NUM_PHYS_REGS)-1:0] first_free_reg;
  logic found_free_reg;

  first_bit_finder #() f (
      .in_use     (in_use),
      .find_true  (0),
      // 1: find first true bit, 0: find first false bit
      .first_index(first_free_reg),
      // 1: valid index found, 0: no valid index (all bits are the same)
      .valid      (found_free_reg)
  );
  always_ff @(posedge clk) begin
    if (!rst) begin
    end else begin
      assert(!(|taken && stall)); // if we are stalled, and consumer still takes the branch, it's invalid

      // allocate logic

      if (found_free_reg) begin
        in_use[first_free_reg] <= 0;
        register[0] <= first_free_reg;
      end
      // free logic
      
      if (valid[0])
        register[freeing_registers][0] <= '0;
      if (valid[1])
        register[freeing_registers][1] <= '1;

      // technically we could check if there are newly freed entries on the same cycle as an allocation is needed, but lowkey, we shouldn't need that very often, and it would only complicate the logic further.
    end

  end

endmodule


// Written by Claude 3.7
// extremely simple implementation, might not scale well w/ so many bits 
// to fpga, so ask Claude to implement binary search or smth
module first_bit_finder #(
) (
    input logic [NUM_PHYS_REGS-1:0] in_use,
    input logic find_true,  // 1: find first true bit, 0: find first false bit
    output logic [$clog2(NUM_PHYS_REGS)-1:0] first_index,
    output logic valid  // 1: valid index found, 0: no valid index (all bits are the same)
);

  logic [NUM_PHYS_REGS-1:0] target_bits;

  // Invert if looking for first false bit
  always_comb begin
    target_bits = find_true ? in_use : ~in_use;
  end

  // Priority encoder implementation
  always_comb begin
    valid = 1'b0;
    first_index = '0;

    for (int i = 0; i < NUM_PHYS_REGS; i++) begin
      if (target_bits[i]) begin
        first_index = i;
        valid = 1'b1;
        break;
      end
    end
  end

endmodule
