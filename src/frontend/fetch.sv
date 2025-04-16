import uop_pkg::*;
import op_pkg::*;

// fetch logic unit.
// will choose from the cacheline received from branch predictor and the pc which instructions
// to send over to decode at most in super_scalar_width.
module fetch #(
    parameter INSTRUCTION_WIDTH = op_pkg::INSTRUCTION_WIDTH,
    parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH,
    parameter CACHE_LINE_WIDTH = 64, 
) (
    input logic clk_in,                                      // clock signal
    input logic rst_N_in,                                    // reset signal, active low                                 
    input logic [7:0] l0_cacheline [CACHE_LINE_WIDTH-1:0],   // cacheline sent from l0
    input logic bp_l0_valid,                                 // branch prediction's cacheline is valid
    input logic[$clog2(SUPER_SCALAR_WIDTH+1)-1:0] pc_valid,  // all pcs valid
    input logic[63:0] pc,                                    // start pc
    input logic [63:0] pred_pc,                              // predicted pc
    output logic [INSTRUCTION_WIDTH-1:0] fetched_cacheline [SUPER_SCALAR_WIDTH-1:0], // instrns to send to decode
    output logic fetch_valid,                                // valid when done (sent to decode)
    output logic fetch_ready,                                // fetch is ready to receive cacheline (sent to bp)
    output logic [63:0] next_pc                              // next PC, predicted from bp to decode
);

localparam int BLOCK_OFFSET_BITS = $clog2(CACHE_LINE_WIDTH);
logic buffer_done;

// start copying over instructions when received a valid cacheline and pc
// pass off the the next predicted pc to decode
always_comb begin: fetch_comb_logic
    if (bp_l0_valid && pc_valid) begin
        for (int i = 0; i < SUPER_SCALAR_WIDTH; i++) begin
            // temp buffer to check next instruction in cacheline
            logic [INSTRUCTION_WIDTH-1:0] temp_instrn_buffer;
            for (int j = 0; j < INSTRUCTION_WIDTH; j = j + 8) begin // 1 byte at a time
                temp_instrn_buffer [j:j+7] = l0_cacheline [pc[BLOCK_OFFSET_BITS:0] + j];
            end
            case (istable[temp_instrn_buffer])
                // Branch Instructions
                OPCODE_B:
                OPCODE_BL:
                OPCODE_B_COND:
                OPCODE_RET:
                    // need to put this in buffer then end fetching
                    fetched_cacheline [i] = temp_instrn_buffer [:];
                    i = SUPER_SCALAR_WIDTH;
                    break;
                OPCODE_LDUR:
                OPCODE_STUR:
                OPCODE_MOVK:
                OPCODE_MOVZ:
                OPCODE_ADRP:
                OPCODE_ADD:
                OPCODE_CMN:
                OPCODE_ADDS:
                OPCODE_SUB:
                OPCODE_CMP:
                OPCODE_SUBS:
                OPCODE_MVN:
                OPCODE_ORR:
                OPCODE_EOR:
                OPCODE_TST:
                OPCODE_ANDS:
                OPCODE_LSR:
                OPCODE_LSL:
                OPCODE_UBFM:
                OPCODE_ASR:
                OPCODE_NOP:
                OPCODE_HLT:
                OPCODE_F_LDUR:
                OPCODE_F_STUR:
                    fetched_cacheline [i] = temp_instrn_buffer [:];
                    break;
                default: begin
                    // idk we shouldn't be here
                end
            endcase
        end
        buffer_done = 1;
    end else begin
        buffer_done = 0;
    end
end

// ctrl signals to keep checking for on every posedge of the clock
always_ff@(posedge clk_in) begin
    if (rst_N_in) begin
        if (buffer_done) begin
            next_pc <= pred_pc;
            fetch_valid <= 1'b1;
            fetch_ready <= 1'b0;
        end else begin
            next_pc <= '0;
            fetch_valid <= 1'b0;
            fetch_ready <= 1'b1;
        end
    end else begin
        fetch_valid <= 1'b0;
        fetch_ready <= 1'b1;
    end
end


endmodule