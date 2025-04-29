`include "../packages/rob_pkg.sv"
`ifndef FRL_SV
`define FRL_SV
import rob_pkg::*;

module frl (
    input  logic clk,
    input  logic rst_N_in,
    input  logic [2 * 4 * uop_pkg::INSTR_Q_WIDTH-1:0] acquire_ready_in,
    output logic acquire_valid_out,
    output logic [2 * 4 * uop_pkg::INSTR_Q_WIDTH-1:0][$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] registers_out,

    input  logic [4 * uop_pkg::INSTR_Q_WIDTH-1:0] free_valid_in,
    input  logic [4 * uop_pkg::INSTR_Q_WIDTH-1:0][$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] freeing_registers
);
  localparam MAX_NUM_REGS = 4 * uop_pkg::INSTR_Q_WIDTH;
  // === STATE ===
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] phys_regs_r [reg_pkg::NUM_PHYS_REGS];
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] phys_reg_indices_r [reg_pkg::NUM_PHYS_REGS];
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] head_r, tail_r;

  // === NEXT STATE ===
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] phys_regs_n [reg_pkg::NUM_PHYS_REGS];
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] phys_reg_indices_n [reg_pkg::NUM_PHYS_REGS];
  logic [$clog2(reg_pkg::NUM_PHYS_REGS)-1:0] head_n, tail_n;

  logic [$clog2(reg_pkg::NUM_PHYS_REGS):0] num_free_regs;

  logic offset;
  int frl_offset;

  // === COMBINATIONAL NEXT-STATE LOGIC ===
  always_comb begin
    // Default next state to current state
    phys_regs_n = phys_regs_r;
    phys_reg_indices_n = phys_reg_indices_r;
    head_n = head_r;
    tail_n = tail_r;

    // === Handle freeing ===
    for (int i = 0; i < MAX_NUM_REGS; i++) begin
      if (free_valid_in[i]) begin
        phys_regs_n[tail_n] = freeing_registers[i];
        phys_reg_indices_n[freeing_registers[i]] = tail_n;
        tail_n = (tail_n + 1 == reg_pkg::NUM_PHYS_REGS) ? 0 : tail_n + 1;
      end
    end

    // === Handle acquiring ===
    for (int i = frl_offset; i < frl_offset + MAX_NUM_REGS; i++) begin
      if (acquire_ready_in[i]) begin
        $display("[FRL] Acquired reg %0d", phys_regs_r[head_n]);
        head_n = (head_n + 1 == reg_pkg::NUM_PHYS_REGS) ? 0 : head_n + 1;
      end
    end

    num_free_regs = (tail_n - head_n + (reg_pkg::NUM_PHYS_REGS));

    // === Output ===
    if (num_free_regs < 2 * MAX_NUM_REGS) begin
      acquire_valid_out = 1'b0;
      registers_out = '0;
    end else begin
      acquire_valid_out = 1'b1;
      for (int i = 0; i < 2 * MAX_NUM_REGS; i++) begin
        registers_out[i] = phys_regs_r[(head_r + i) % reg_pkg::NUM_PHYS_REGS];
      end
    end
    $display("[FRL] %0d free regs, head is at %0d", num_free_regs, head_n);
  end

  // === STATE REGISTER UPDATE ===
  always_ff @(posedge clk) begin
    if (~rst_N_in) begin
      for (int i = 0; i < reg_pkg::NUM_PHYS_REGS; i++) begin
        phys_regs_r[i] <= i[$clog2(reg_pkg::NUM_PHYS_REGS)-1:0];
        phys_reg_indices_r[i] <= i[$clog2(reg_pkg::NUM_PHYS_REGS)-1:0];
      end
      head_r <= 0;
      tail_r <= 0;
      frl_offset <= 0;
      offset <= 0;
    end else begin
      offset <= ~offset;
      frl_offset <= offset ? 0 : MAX_NUM_REGS;
      phys_regs_r <= phys_regs_n;
      phys_reg_indices_r <= phys_reg_indices_n;
      head_r <= head_n;
      tail_r <= tail_n;
    end
  end

endmodule
`endif // FRL_SV
