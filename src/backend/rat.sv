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
    input logic clk,
    input logic rst,
    input logic [1:0] acquire_valid_in,
    input logic [1:0] free_valid_in,
    input logic [1:0][$clog2(NUM_PHYS_REGS) - 1:0] freeing_registers,
    output logic [1:0][$clog2(NUM_PHYS_REGS) - 1:0] registers_out,
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

  // TODO: This module will break if the list is overfilled or overfreed
  // Does not support freeing and acquiring a register in the same cycle

  // Implementation: Use a bitmap to represent all physical registers.
  // Use a circular queue to represent all free registers
  // Output a signal indicating number of free registers
  // When a register is used, increment head and output the head's index
  // When a register is freed, replace that index with the tail increment the tail
  // Compute difference between head and tail to find number of free registers

  logic [NUM_PHYS_REGS-1:0] phys_regs; // Bitmap representing all physical registers
  logic [$clog2(NUM_PHYS_REGS)-1:0] head, // Points to the next free entry
                                    tail; // Points to the next entry to free

  always_ff @(posedge clk) begin

    if (rst) begin
      // Initialize queue to empty with head and tail at beginning index
      phys_regs <= '0;
      head <= '0;
      tail <= '0;
    end else begin
      // If freeing
      if (free_valid_in[1] || free_valid_in[0]) begin
        for (int i = 0; i < 2; i++) begin
          if (free_valid_in[i]) begin
            phys_regs[freeing_registers[i]] <= phys_regs[tail]; // Replace with tail
            phys_regs[tail] <= '0; // Free this 
            tail <= tail + 1;
          end
        end
      end
      else begin // Get free register (and trust that there is even a register to get)
        for (int i = 0; i < 2; i++) begin
          if (acquire_valid_in[i]) begin
            registers_out[i] <= head; // Recall that head points to next free register
            phys_regs[head] <= 1; // Mark as used
            head <= head + 1;
          end
        end
      end

      // Logic for computing number of free registers
      if (tail > head) begin
        assign num_free_regs = head + (128 - tail); // Parentheses to not overflow head before subtracting tail
      else
        assign num_free_regs = head - tail;

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
