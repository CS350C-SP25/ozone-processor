`include "../packages/rob_pkg.sv"

import rob_pkg::*;


module frl #(
) (
    input   logic clk,
    input   logic rst,
    input   logic [3:0] acquire_ready_in, // Mask for upstream module to indicate which registers it accepted on previous cycle
    output  logic acquire_valid_out, // registers_out is valid. If this is 0, this module is stalling
    output  logic [3:0][$clog2(reg_pkg::NUM_PHYS_REGS) - 1:0] registers_out, // Free registers the upstream module can use.if acquire_valid_out is 0

    input   logic [5:0] free_valid_in,
    input   logic [5:0][$clog2(reg_pkg::NUM_PHYS_REGS) - 1:0] freeing_registers
);

  logic [reg_pkg::NUM_PHYS_REGS-1:0] [$clog2(reg_pkg::NUM_PHYS_REGS) - 1:0] phys_regs, // The queue. Physical registers are stored at indices, 
                                                                     // not necessarily in order.
                                                          phys_reg_indices; // Physical register mapping. Physical register as index,
                                                                            // queue index stored at that index
  
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] head, // Points to the next free entry. Points to tail when the queue is empty or full.
                                    tail, // Points to the next entry to free
                                    temp_index, // Temp signal for swapping mapping indices
                                    num_free_regs; // Number of free registers

  logic empty; // Internal signal for when the queue is empty. Necessary because a full queue and empty queue look identical.

  /*
    Procedure:
    1. Check the acquire_ready_in. This will indicate which registers were accepted upstream.
           This will be the most challenging part. We will just assume the register is still free by default.
           If it turns out to be taken (1) then actually mark the register as taken.
    2. Free registers in freeing_registers
           Swap the freed register with the tail of the queue and increment tail
    3. Provide 4 registers.
           Check if there are even 4 free registers.
           If so, set acquire_valid_out to 1 and put the 4 registers on registers_out
           If not, set acquire_valid_out to 0 (stall)
  */

  always_ff @(posedge clk) begin

    if (rst) begin
      // Default mapping. Map all registers to normal indices
      for (int i = 0; i < reg_pkg::NUM_PHYS_REGS; i++) begin
         // Only use bottom order bits of i
        phys_regs[i] <= i[$clog2(reg_pkg::NUM_PHYS_REGS)-1:0];
        phys_reg_indices[i] <= i[$clog2(reg_pkg::NUM_PHYS_REGS)-1:0];
      end

      head <= '0;
      tail <= '0;
      empty <= '1;

    end else begin
    
      // Check which registers were accepted on previous cycle
      // We will swap an accepted register to the tail of the queue
      // We will know which registers this corresponds to using the index of acquire_ready_in as the offset from head
      
      // Free registers
      // WARNING: Will break if you're freeing registers that were never acquired!
      for (int i = 0; i < 6; i++) begin
        if (free_valid_in[i]) begin
          
          // TODO: This needs to be combinational!

          // Swap places in queue
          temp_index <= phys_reg_indices[freeing_registers[i]]; // Store the queue index of the register we are freeing

          // Swap the indices of the registers whose places in the queue we are swapping
          phys_reg_indices[freeing_registers[i]] <= tail; // Change freeing register's index to the tail
          phys_reg_indices[phys_regs[tail]] <= temp_index; // Change index of register at tail to that of the freeing register

          // Swap register places in queuequeue
          phys_regs[temp_index] <= phys_regs[tail]; // Move tail to freeing register's index
          phys_regs[tail] <= freeing_registers[i]; // Move freeing register to tail's index
          
          tail <= tail + 1; // Increment tail
          if (head == tail) begin
            empty <= '1;
          end
        end
      end

      // WARNING: This will break if the lowest order register signals were not used first!
      // For each register that could have been acquired
      for (int i = 0; i < 6; i++) begin
        if (acquire_ready_in[i]) begin // If this register was acquired
          head <= head + 1;
          empty <= '0;
        end else begin
          break;
        end
      end

      // Logic for computing number of free registers
      if (tail > head) begin
        num_free_regs <= head + ({(reg_pkg::NUM_PHYS_REGS-1){1'b1}} - tail); // Parentheses to not overflow head before subtracting tail
      end else if (!empty) begin
        num_free_regs <= head - tail;
      end else begin
        num_free_regs <= {(reg_pkg::NUM_PHYS_REGS-1){1'b1}}; // Max value, all registers are free
      end
      
      if (num_free_regs < 6) begin
        acquire_valid_out <= '0; // Stall
      end else begin
        // For each free register to provide
        for (int i = 0; i < 6; i++) begin
          registers_out[i] <= head + i;
        end
      end

    end

  end

endmodule

