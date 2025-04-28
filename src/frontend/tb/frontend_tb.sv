

`ifndef FE_TB
`define FE_TB

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
    logic lc_ready_in;
    logic lc_valid_in;
    logic [63:0] lc_addr_in;
    logic [511:0] lc_value_in;
    logic lc_valid_out;
    logic lc_ready_out;
    logic [63:0] lc_addr_out;
    logic [511:0] lc_value_out;
    logic lc_we_out;
    logic exe_ready;
    uop_insn  instruction_queue_in[INSTR_Q_WIDTH-1:0];
    logic [7:0] mem [0:MEM_SIZE-1];
    logic start;

    frontend #(
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH),
        .SUPER_SCALAR_WIDTH(SUPER_SCALAR_WIDTH),
        .CACHE_LINE_WIDTH(CACHE_LINE_WIDTH)
    ) dut (
        .clk_in(clk_in),
        .rst_N_in(rst_N_in),
        .cs_N_in(cs_N_in),
        .start(start),
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
        .instruction_queue_in(instruction_queue_in)
    );

    // Clock generation
    initial begin
        clk_in = 0;
        forever #10 clk_in = ~clk_in;
    end

    // Memory initialization
    initial begin
        // Define instructions according to the microarch chart
        logic [31:0] instructions [0:17];
                logic [63:0] addr = 64'h0;

        // Original instructions: 8 ADDs (alternating)
        instructions[0] = 32'h91000001; // ADD x0, x0, #0
        instructions[1] = 32'h91000001; // ADD x1, x0, #0
        instructions[2] = 32'h91000001;
        instructions[3] = 32'h91000001;
        instructions[4] = 32'h91000001;
        instructions[5] = 32'h91000001;
        instructions[6] = 32'h91000000;
        instructions[7] = 32'h91000001;
        // New instructions (corrected per chart)
        instructions[8]  = 32'hD2BFFFE0; // MOVZ x0, #0xFFFF
        instructions[9]  = 32'hD2DFFFE1; // MOVZ x1, #0xFFFF, lsl 16
        instructions[10] = 32'hD2FFFFE2; // MOVZ x2, #0xFFFF, lsl 32
        instructions[11] = 32'hD2FFFBE3; // MOVZ x3, #0xFFFF, lsl 48
        instructions[12] = 32'hD2800024; // MOVZ x4, #1
        instructions[13] = 32'hEB0100A5; // ADDS x5, x0, x1
        instructions[14] = 32'hEB0300C6; // ADDS x6, x2, x3
        instructions[15] = 32'hEB0600E7; // ADDS x7, x5, x6
        instructions[16] = 32'hEB070108; // ADDS x8, x4, x7
        instructions[17] = 32'hD4000000; // HLT

        // Load instructions into memory (big-endian)
        for (int i = 0; i < 18; i++) begin
            logic [31:0] instr = instructions[i];
mem[12'(addr + i*4 + 0)] = instr[ 7:0];   // LSB first
mem[12'(addr + i*4 + 1)] = instr[15:8];
mem[12'(addr + i*4 + 2)] = instr[23:16];   //this casting might be cooked
mem[12'(addr + i*4 + 3)] = instr[31:24];  // MSB last
        end

        // Debug output for memory contents
        $display("Instructions loaded into simulated memory:");
        for (int i = 0; i < 18; i++) begin
            logic [63:0] pc = addr + i*4;
            $display("  Instr at 0x%h: %h %h %h %h // %s", pc, 
                     mem[12'(pc)+0], mem[12'(pc)+1], mem[12'(pc)+2], mem[12'(pc)+3],
                     i < 8 ? (i % 2 == 0 ? "ADD x0, x0, #0" : "ADD x1, x0, #0") :
                     i == 8 ? "MOVZ x0, #0xffff" :
                     i == 9 ? "MOVZ x1, #0xffff, lsl 16" :
                     i == 10 ? "MOVZ x2, #0xffff, lsl 32" :
                     i == 11 ? "MOVZ x3, #0xffff, lsl 48" :
                     i == 12 ? "MOVZ x4, #1" :
                     i == 13 ? "ADDS x5, x0, x1" :
                     i == 14 ? "ADDS x6, x2, x3" :
                     i == 15 ? "ADDS x7, x5, x6" :
                     i == 16 ? "ADDS x8, x4, x7" : "HLT");
        end
    end

    // Reset and simulation control
    initial begin
        rst_N_in = 0;
        cs_N_in = 1;
        start = 1;
        x_bcond_resolved = 0;
        x_pc_incorrect = 0;
        x_taken = 0;
        x_pc = 0;
        x_correction_offset = 0;
        lc_ready_in = 1; // LLC always ready to accept requests
        lc_valid_in = 0;
        lc_addr_in = 0;
        lc_value_in = 0;
        exe_ready = 1;

        #30;
        rst_N_in = 1;
        cs_N_in = 0;
        #10;
        start = 0;



        #3000; // Observe single block
        $finish;
    end

    // LLC simulation with state machine
    logic [63:0] req_addr;
    int latency_counter;
    enum {IDLE, WAIT_LATENCY, SEND_DATA} state;

    initial state = IDLE;

    always @(posedge clk_in) begin
        case (state)
            IDLE: begin
                lc_valid_in <= 0;
                if (lc_valid_out && lc_ready_in) begin
                    $display("Time: %0t | LLC Request Received - Addr: 0x%h", $time, lc_addr_out);
                    req_addr <= lc_addr_out;
                    state <= WAIT_LATENCY;
                    latency_counter <= 5; // Simulate 5-cycle memory latency
                end
            end
            WAIT_LATENCY: begin
                if (latency_counter > 0) begin
                    latency_counter <= latency_counter - 1;
                end else begin
                    state <= SEND_DATA;
                end
            end
            SEND_DATA: begin
                lc_valid_in <= 1;
                lc_addr_in <= req_addr;
                for (longint i = 0; i < CACHE_LINE_BYTES; i++) begin
                    logic [63:0] mem_addr = (req_addr & ~63) + i; // Align to cache line
                    if (mem_addr < MEM_SIZE) begin
                        lc_value_in[9'(i*8) +: 8] <= mem[12'(mem_addr)];
                    end else begin
                        lc_value_in[9'(i*8) +: 8] <= 8'h00;
                    end
                end
                $display("Time: %0t | LLC Response Sent - Addr: 0x%h, First 8 bytes: %h %h %h %h %h %h %h %h",
                         $time, lc_addr_in,
                         lc_value_in[7:0], lc_value_in[15:8], lc_value_in[23:16], lc_value_in[31:24],
                         lc_value_in[39:32], lc_value_in[47:40], lc_value_in[55:48], lc_value_in[63:56]);
                if (lc_ready_out) begin
                    state <= IDLE;
                    lc_valid_in <= 0;
                end
            end
        endcase
    end

    // Debug output for decoded instructions
    always @(posedge clk_in) begin
        if (rst_N_in && !cs_N_in) begin
            // if (dut.decode_stage.decode_ready) begin
                $display("Time: %0t | Decoded Instructions:", $time);
                for (int i = 0; i < INSTR_Q_WIDTH; i++) begin
                    if (instruction_queue_in[i].uopcode != UOP_NOP) begin

                $display("  uop[%0d]: %-12s pc=0x%h",
                 i, instruction_queue_in[i].uopcode.name(), instruction_queue_in[i].pc);
                    end
                end
            // end
            $display("Time: %0t | BP State: current_pc=0x%h, l1i_addr_out_next=0x%h, l1i_valid=%b, bp_l0_valid=%b, instructions_inflight=%d",
                     $time, dut.bp.current_pc, dut.bp.l1i_addr_out_next, 
                     dut.bp.l1i_valid, dut.bp.bp_l0_valid, dut.bp.instructions_inflight);
        end
    end

endmodule

`endif