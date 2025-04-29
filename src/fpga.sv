`include "ozone.sv"

// backend only for now lets see
module fpga (
    input logic FPGA_CLK3_50,
    input logic[0:0] KEY,
    output logic [3:0] debug_out,
    output logic[5:0] LED       // <-- add output for blinking LED
);
  import uop_pkg::*;

  // Declare and initialize fake_q properly
  instr_queue_t fake_q;

  logic taken;
  logic [63:0] pc;
  logic [18:0] correction;
  logic exec_ready;

  // Clock divider: divide 50 MHz to 10 Hz (divide by 5,000,000)
  logic [22:0] clkdiv_counter = 0;
  logic clk_10hz = 0;

  always_ff @(posedge FPGA_CLK3_50) begin
    if (clkdiv_counter == 23'd4_999_999) begin
      clkdiv_counter <= 0;
      clk_10hz <= ~clk_10hz;
    end else begin
      clkdiv_counter <= clkdiv_counter + 1;
    end
  end

  // LED blink logic: toggles every 2 cycles of 10 Hz clock (i.e., 5 Hz blink)
  logic blink_ff = 0;
  always_ff @(posedge clk_10hz) begin
    blink_ff <= ~blink_ff;
  end

  assign LED[0] = blink_ff;
  assign LED[1] = ~blink_ff;
  assign LED[2] = blink_ff;
  assign LED[3] = ~blink_ff;

  initial begin
    fake_q[0].uopcode   = UOP_EOR;
    fake_q[0].data      = '0;
    fake_q[0].pc        = 64'd0;
    fake_q[0].valb_sel  = 0;
    fake_q[0].mem_read  = 0;
    fake_q[0].mem_write = 0;
    fake_q[0].w_enable  = 1;
    fake_q[0].tx_begin  = 0;
    fake_q[0].tx_end    = 0;
    fake_q[0].valid     = 1;

    fake_q[1].uopcode   = UOP_EOR;
    fake_q[1].data      = '0;
    fake_q[1].pc        = 64'd0;
    fake_q[1].valb_sel  = 0;
    fake_q[1].mem_read  = 0;
    fake_q[1].mem_write = 0;
    fake_q[1].w_enable  = 1;
    fake_q[1].tx_begin  = 0;
    fake_q[1].tx_end    = 0;
    fake_q[1].valid     = 1;

    fake_q[2].uopcode   = UOP_EOR;
    fake_q[2].data      = '0;
    fake_q[2].pc        = 64'd0;
    fake_q[2].valb_sel  = 0;
    fake_q[2].mem_read  = 0;
    fake_q[2].mem_write = 0;
    fake_q[2].w_enable  = 1;
    fake_q[2].tx_begin  = 0;
    fake_q[2].tx_end    = 0;
    fake_q[2].valid     = 1;

    fake_q[3].uopcode   = UOP_EOR;
    fake_q[3].data      = '0;
    fake_q[3].pc        = 64'd0;
    fake_q[3].valb_sel  = 0;
    fake_q[3].mem_read  = 0;
    fake_q[3].mem_write = 0;
    fake_q[3].w_enable  = 1;
    fake_q[3].tx_begin  = 0;
    fake_q[3].tx_end    = 0;
    fake_q[3].valid     = 1;
  end

  always_comb begin
    // Expose backend signals to top-level output to prevent optimization
    debug_out = {taken, exec_ready, correction[1:0]};
  end

 (* keep_hierarchy *) backend be (
      .clk_in(clk_10hz), // use divided clock
      .rst_N_in(KEY[0]),
      .instr_queue(fake_q),
      .bcond_resolved_out(),
      .pc_incorrect_out(),  // this means that the PC that we had originally predicted was incorrect. We need to fix.
      .taken_out(taken),  // if the branch resolved as taken or not -- to update PHT and GHR
      .pc_out(pc),  // pc that is currently in the exec phase (the one that just was resolved)
      .correction_offset_out(correction), // the offset of the correction from x_pc (could change this to be just the actual correct PC instead ??)
      .ready_out(exec_ready)
  );

endmodule
