`include "../packages/rob_pkg.sv"
`ifndef FRL_SV
`define FRL_SV
import rob_pkg::*;


module frl #(
  parameter MAX_NUM_REGS = 3 * uop_pkg::INSTR_Q_WIDTH
) (
    input  logic clk,
    input  logic rst,
    input  logic [MAX_NUM_REGS - 1:0] acquire_ready_in,
    output logic acquire_valid_out,
    output logic [MAX_NUM_REGS - 1:0][$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] registers_out,

    input  logic [MAX_NUM_REGS - 1:0] free_valid_in,
    input  logic [MAX_NUM_REGS - 1:0][$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] freeing_registers
);

  // === STATE ===
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] phys_regs_r [reg_pkg::NUM_PHYS_REGS];
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] phys_reg_indices_r [reg_pkg::NUM_PHYS_REGS];
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] head_r, tail_r;
  logic empty_r;

  // === NEXT STATE ===
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] phys_regs_n [reg_pkg::NUM_PHYS_REGS];
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] phys_reg_indices_n [reg_pkg::NUM_PHYS_REGS];
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] head_n, tail_n;
  logic empty_n;

  logic [$clog2(reg_pkg::NUM_PHYS_REGS):0] num_free_regs;

  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] temp_indices [2*uop_pkg::INSTR_Q_WIDTH+1:0];

  // === COMBINATIONAL NEXT-STATE LOGIC ===
  always_comb begin
    // Default next state to current state
    phys_regs_n = phys_regs_r;
    phys_reg_indices_n = phys_reg_indices_r;
    head_n = head_r;
    tail_n = tail_r;
    empty_n = empty_r;

    // Handle freeing registers
    for (int i = 0; i < MAX_NUM_REGS; i++) begin
      if (free_valid_in[i]) begin
        temp_indices[i] = phys_reg_indices_r[freeing_registers[i]];

        // Swap entries in queue
        phys_regs_n[temp_indices[i]] = phys_regs_r[tail_n];
        phys_regs_n[tail_n]     = freeing_registers[i];

        // Update index mapping
        phys_reg_indices_n[phys_regs_r[tail_n]]     = temp_indices[i];
        phys_reg_indices_n[freeing_registers[i]]    = tail_n;

        tail_n = tail_n + 1;
        if (tail_n + 1 == head_r)
          empty_n = 1'b1;
      end else begin
        temp_indices[i] = 'x; // Avoids inferred latch
      end
    end

    // Handle acquired registers
    for (int i = 0; i < MAX_NUM_REGS; i++) begin
      if (acquire_ready_in[i]) begin
        head_n = head_n + 1;
        empty_n = 1'b0;
      end
    end

    // Compute number of free regs
    if (tail_n >= head_n)
      num_free_regs = ($clog2(reg_pkg::NUM_PHYS_REGS) + 1)'(reg_pkg::NUM_PHYS_REGS - ($clog2(reg_pkg::NUM_PHYS_REGS))'(tail_n - head_n));
    else
      num_free_regs = head_n - tail_n;

    // Output free registers
    // v e r i l a t o r   is FORCING ME to pad this value
    if ({{(reg_pkg::NUM_PHYS_REGS - $clog2(reg_pkg::NUM_PHYS_REGS)){1'b0}}, num_free_regs} < MAX_NUM_REGS + 1) begin // I hate SystemVerilog
      acquire_valid_out = 1'b0;
      registers_out = '0;
    end else begin
      acquire_valid_out = 1'b1;
      for (int i = 0; i < MAX_NUM_REGS; i++) begin
        registers_out[i] = phys_regs_r[($clog2(reg_pkg::NUM_PHYS_REGS))'(head_r + i)];
      end
    end
  end

  // === STATE REGISTER UPDATE ===
  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < reg_pkg::NUM_PHYS_REGS; i++) begin
        phys_regs_r[i]        <= i[$clog2(reg_pkg::NUM_PHYS_REGS)-1:0];
        phys_reg_indices_r[i] <= i[$clog2(reg_pkg::NUM_PHYS_REGS)-1:0];
      end
      head_r <= 0;
      tail_r <= 0;
      empty_r <= 1'b1;
    end else begin
      phys_regs_r        <= phys_regs_n;
      phys_reg_indices_r <= phys_reg_indices_n;
      head_r <= head_n;
      tail_r <= tail_n;
      empty_r <= empty_n;
    end
  end

endmodule
`endif // FRL_SV