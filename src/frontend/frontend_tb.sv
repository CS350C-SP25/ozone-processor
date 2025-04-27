`include "../util/uop_pkg.sv"
`include "../util/op_pkg.sv"
import op_pkg::*;
import uop_pkg::*;

module frontend_tb;

    localparam INSTRUCTION_WIDTH = 32;
    localparam SUPER_SCALAR_WIDTH = 2;
    localparam CACHE_LINE_BYTES = 64;
    localparam CACHE_LINE_WIDTH = CACHE_LINE_BYTES;
    localparam INSTR_Q_WIDTH = 4;
    localparam MEM_SIZE = 4096;

    logic clk_in;
    logic rst_N_in;
    logic cs_N_in;
    logic x_bcond_resolved;
    logic x_pc_incorrect;
    logic x_taken;
    logic [63:0] x_pc;
    logic [18:0] x_correction_offset;
    logic lc_ready_in = 1;
    logic lc_valid_in;
    logic [63:0] lc_addr_in;
    logic [511:0] lc_value_in;
    logic lc_valid_out;
    logic lc_ready_out;
    logic [63:0] lc_addr_out;
    logic [511:0] lc_value_out;
    logic lc_we_out;
    logic exe_ready;
    logic [$clog2(INSTR_Q_WIDTH+1)-1:0] instruction_queue_pushes;
    uop_insn instruction_queue_in [INSTR_Q_WIDTH-1:0];
    logic [7:0] mem [0:MEM_SIZE-1];

    frontend #(
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH),
        .SUPER_SCALAR_WIDTH(SUPER_SCALAR_WIDTH),
        .CACHE_LINE_WIDTH(CACHE_LINE_WIDTH)
    ) dut (
        .clk_in(clk_in),
        .rst_N_in(rst_N_in),
        .cs_N_in(cs_N_in),

        .start(1'b1),
        .start_pc('0),

        .x_bcond_resolved(x_bcond_resolved),
        .x_pc_incorrect(x_pc_incorrect),
        .x_taken(x_taken),
        .x_pc(x_pc),
        .x_correction_offset(x_correction_offset),
        .lc_ready_in(lc_ready_in),
        .lc_valid_in(lc_valid_in),
        .lc_addr_in(lc_addr_in),
        .lc_value_in(lc_value_in),
        .exe_ready(exe_ready),
        .lc_valid_out(lc_valid_out),
        .lc_ready_out(lc_ready_out),
        .lc_addr_out(lc_addr_out),
        .lc_value_out(lc_value_out),
        .lc_we_out(lc_we_out),
        // .instruction_queue_pushes(instruction_queue_pushes),
        .instruction_queue_in(instruction_queue_in)
    );

    initial begin
        clk_in = 0;
        forever #5 clk_in = ~clk_in;
    end

    initial begin
        logic [63:0] addr = 64'h0;
        mem[12'(addr + 0)] = 8'h00;
        mem[12'(addr) + 1] = 8'h00;
        mem[12'(addr) + 2] = 8'h00;
        mem[12'(addr) + 3] = 8'h91;
        mem[12'(addr) + 4] = 8'h01;
        mem[12'(addr) + 5] = 8'h00;
        mem[12'(addr) + 6] = 8'h00;
        mem[12'(addr) + 7] = 8'h91;
        for (longint i = 8; i < CACHE_LINE_BYTES; i += 4) begin
            mem[12'(addr + i + 0)] = 8'h1F;
            mem[12'(addr + i + 1)] = 8'h20;
            mem[12'(addr + i + 2)] = 8'h03;
            mem[12'(addr + i + 3)] = 8'hD5;
        end
        $display("Instructions loaded into simulated memory:");
        $display("  Instr at 0x%h: %h %h %h %h // ADD x0, x0, #0", addr, mem[12'(addr)+3], mem[12'(addr)+2], mem[12'(addr)+1], mem[12'(addr)+0]);
        $display("  Instr at 0x%h: %h %h %h %h // ADD x1, x0, #0", addr+4, mem[12'(addr)+7], mem[12'(addr)+6], mem[12'(addr)+5], mem[12'(addr)+4]);
        $display("  Instr at 0x%h: %h %h %h %h // NOP", addr+8, mem[12'(addr)+11], mem[12'(addr)+10], mem[12'(addr)+9], mem[12'(addr)+8]);
    end

    initial begin
        rst_N_in = 0;
        cs_N_in = 1;
        x_bcond_resolved = 0;
        x_pc_incorrect = 0;
        x_taken = 0;
        x_pc = 0;
        x_correction_offset = 0;
        lc_ready_in = 1;
        lc_valid_in = 0;
        lc_addr_in = 0;
        lc_value_in = 0;
        exe_ready = 1;

        #20;
        rst_N_in = 1;
        cs_N_in = 0;

        #5000; // Extended to see instruction output
        $finish;
    end

    always @(posedge clk_in) begin
        if (lc_valid_out && lc_ready_in) begin
            $display("lc here hmph");
            repeat (5) @(posedge clk_in);
            lc_valid_in <= 1;
            lc_addr_in <= lc_addr_out;
            for (longint i = 0; i < CACHE_LINE_BYTES; i++) begin
                logic [63:0] mem_addr = lc_addr_out + i;
                if (mem_addr < MEM_SIZE) begin
                    lc_value_in[9'(i*8) +: 8] <= mem[12'(mem_addr)];
                end else begin
                    lc_value_in[9'(i*8) +: 8] <= 8'h1F;
                end
            end
            // @(posedge clk_in);
            // lc_valid_in <= 0;
        end
        else begin
            $display("lc not valid and not ready");
        end
    end

    always @(posedge clk_in) begin
        if (rst_N_in && !cs_N_in) begin
            $display("Time: %0t | BP Pred_PC: 0x%h | PC_Valid: %b | L1I_Req: %b | L0_Hit: %b",
                     $time, dut.bp.pred_pc, dut.bp.pc_valid_out, dut.bp.bp_l1i_valid_out, dut.bp.l0_hit);
            $display("Time: %0t | L1I State: %s", $time, dut.l1i.cur_state.name());
            if (lc_valid_out)
                $display("Time: %0t | LLC Request - Addr: 0x%h", $time, lc_addr_out);
            if (lc_valid_in) begin
                $display("Time: %0t | LLC Response - Addr: 0x%h, First 8 bytes: %h %h %h %h %h %h %h %h",
                         $time, lc_addr_in,
                         lc_value_in[7:0], lc_value_in[15:8], lc_value_in[23:16], lc_value_in[31:24],
                         lc_value_in[39:32], lc_value_in[47:40], lc_value_in[55:48], lc_value_in[63:56]);
            end
        end
    end

endmodule