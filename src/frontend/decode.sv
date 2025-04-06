import uop_pkg::*;
import op_pkg::*;

module decode #(
    parameter INSTRUCTION_WIDTH = op_pkg::INSTRUCTION_WIDTH,
    parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH,
    parameter INSTR_Q_DEPTH = uop_pkg::INSTR_Q_DEPTH,
    parameter INSTR_Q_WIDTH = uop_pkg::INSTR_Q_WIDTH
) (
    input logic clk_in,
    input logic rst_N_in,
    input logic flush_in,
    input logic [SUPER_SCALAR_WIDTH-1:0][INSTRUCTION_WIDTH-1:0] fetched_ops,
    input opcode_t [SUPER_SCALAR_WIDTH-1:0] opcode,
    input uop_branch [SUPER_SCALAR_WIDTH-1:0] branch_data,
    input logic [SUPER_SCALAR_WIDTH-1:0][63:0] pc,
    input logic fetch_valid,
    input logic exe_ready,
    output logic decode_ready,
    output logic decode_valid,
    output logic [$clog2(INSTR_Q_WIDTH+1)-1:0] instruction_queue_pushes,
    output uop_insn[INSTR_Q_WIDTH-1:0] instruction_queue_in
);
    uop_insn [INSTR_Q_WIDTH-1:0] enq_next;
    logic [$clog2(INSTR_Q_WIDTH+1)-1:0] enq_width;

    uop_insn [INSTR_Q_WIDTH-1:0] buffer;
    logic [$clog2(INSTR_Q_WIDTH+1)-1:0] buffer_width,
    logic buffered;
    always_ff @(posedge clk_in) begin : decode_fsm
        if (rst_N_in && !flush_in) begin
            if (fetch_valid) begin
                if (exe_ready) begin
                    instruction_queue_in <= buffered ? buffer : enq_next;
                    instruction_queue_pushes <= buffered ? buffer_width : enq_width;
                    buffered <= buffered; //this should be 0 if the fsm is working correctly 
                    buffer <= enq_next; 
                    buffer_width <= enq_width;
                    decode_valid <= 1'b1;
                    decode_ready <= 1'b1;
                end else begin
                    buffer <= enq_next;
                    buffer_width <= enq_width;
                    buffered <= 1'b1;
                    decode_valid <= 1'b0;
                    decode_ready <= 1'b0;
                end
            end else begin
                if (exe_ready) begin
                    instruction_queue_in <= buffer;
                    instruction_queue_pushes <= buffered ? buffer_width : '0;
                    buffered <= '0;
                    decode_valid <= '1;
                    decode_ready <= '1;
                end else begin
                    instruction_queue_pushes <= '0;
                    decode_ready <= ~buffered;
                    buffered <= buffered;
                    decode_valid <= '0;
                end
            end
        end else begin
            buffered = '0;
            buffer_width = '0;
            decode_valid <= 1'b0;
            decode_ready <= 1'b0;
            instruction_queue_pushes <= '0;
        end
    end

    always_comb begin : decode_comb_logic
        function automatic void decode_m_format_add(
            input logic[INSTR_Q_WIDTH-1:0] op_bits,
            output uop_insn uop_out 
        );
            uop_ri ri;
            ri.dst.gpr = op_bits[4:0];
            ri.dst.is_sp = '0;
            ri.dst.is_fp = '0; // if we are adding then this isnt a fop 
            ri.src.gpr = op_bits[9:5];
            ri.src.is_sp = &op_bits[9:5];
            ri.src.is_fp = '0;
            ri.imm = {12'b0, op_bits[20:12]};
            ri.set_nzcv = '0;
            set_data_ri(ri, uop_out.data);
            uop_out.valb_sel = '0 //use imm (there is no src2)
            uop_out.mem_read = '0;
            uop_out.mem_write = '0;
            uop_out.w_enable = '1;
            uop_out.uop_code = op_bits[20] ? UOP_SUB : UOP_ADD; //add and sub are unsigned
            uop_out.tx_begin = 1'b1;
            uop_out.tx_end = 1'b0;
        endfunction

        function automatic void decode_m_format_mem(
            input logic[INSTRUCTION_WIDTH-1:0] op_bits,
            output uop_insn uop_out 
        );
            uop_ri ri;
            ri.dst.gpr = op_bits[4:0];
            ri.dst.is_sp = '0;
            ri.dst.is_fp = op_bits[26];
            ri.src.gpr = op_bits[20:12] == 0 ? op_bits[9:5] : op_bits[4:0]; //if we add we store the add result into dst, then we reuse dst
            ri.src.is_sp = op_bits[20:12] == 0 ? &op_bits[9:5] : '0;
            ri.src.is_fp = '0;
            ri.imm = 21'b0;
            ri.hw = 2'b0;
            ri.set_nzcv = '0;
            set_data_ri(ri, uop_out.data);
            uop_out.valb_sel = '0;
        endfunction

        function automatic void decode_i1_format(
            input logic[INSTRUCTION_WIDTH-1:0] op_bits,
            output uop_insn uop_out
        );
            uop_ri ri;
            ri.dst.gpr = op_bits[4:0];
            ri.dst.is_sp = '0;
            ri.dst.is_fp = '0;
            ri.src.gpr = 5'b0;
            ri.src.is_sp = '0;
            ri.src.is_fp = '0;
            ri.imm = {5'b0, op_bits[20:5]};
            ri.set_nzcv = '0;
            set_data_ri(ri, uop_out.data);
            uop_out.valb_sel = '0;
            uop_out.mem_read = '0;
            uop_out.mem_write = '0;
            uop_out.w_enable = '1;
            uop_out.tx_begin = 1'b1;
            uop_out.tx_end = 1'b1;
        endfunction

        function automatic void decode_i2_format(
            input logic[INSTRUCTION_WIDTH-1:0] op_bits,
            output uop_insn uop_out
        );
            uop_ri ri;
            ri.dst.gpr = op_bits[4:0];
            ri.dst.is_sp = '0;
            ri.dst.is_fp = '0;

            ri.src.gpr = 5'b0;
            ri.src.is_sp = '0;
            ri.src.is_fp = '0;
            ri.imm = {op_bits[30:29], op_bits[23:5]};
            ri.set_nzcv = '0;
            set_data_ri(ri, uop_out.data);
            uop_out.valb_sel = '0;
            uop_out.mem_read = '0;
            uop_out.mem_write = '0;
            uop_out.w_enable = '1;
            uop_out.tx_begin = 1'b1;
            uop_out.tx_end = 1'b1;
        endfunction

        function automatic void decode_rr_format(
            input logic[INSTRUCTION_WIDTH-1:0] op_bits,
            output uop_insn uop_out
        );
            uop_rr rr;
            rr.dst.gpr = op_bits[4:0];
            rr.dst.is_sp = '0;
            rr.dst.is_fp = op_bits[26];
            rr.src1.gpr = op_bits[9:5];
            rr.src1.is_sp = '0;
            rr.src1.is_fp = op_bits[26];
            rr.src2.gpr = op_bits[20:16];
            rr.src2.is_sp = '0;
            rr.src2.is_fp = op_bits[26];
            set_data_rr(ri, uop_out.data);
            uop_out.valb_sel = 1'b1;
            uop_out.mem_read = '0;
            uop_out.mem_write = '0;
            uop_out.w_enable = '1;
            uop_out.tx_begin = 1'b1;
            uop_out.tx_end = 1'b1;
        endfunction

        function automatic void decode_ri_format(
            input logic[INSTRUCTION_WIDTH-1:0] op_bits,
            output uop_insn uop_out
        );
            uop_ri ri;
            ri.dst.gpr = op_bits[4:0];
            ri.dst.is_sp = &op_bits[4:0] & (op_bits[31:22] == 10'b1001000100 | op_bits[31:22] == 10'b1101000100) & &op_bits[9:5];
            ri.dst.is_fp = op_bits[26];
            ri.src.gpr = op_bits[9:5];
            ri.src.is_sp = &op_bits[9:5] & (op_bits[31:22] == 10'b1001000100 | op_bits[31:22] == 10'b1101000100); //ADD or SUB
            ri.src.is_fp = op_bits[26];
            ri.imm = {9'b0, op_bits[21:10]};
            ri.set_nzcv = '0;
            set_data_ri(ri, uop_out.data);
            uop_out.valb_sel = '0;
            uop_out.mem_read = '0;
            uop_out.mem_write = '0;
            uop_out.w_enable = '1;
            uop_out.tx_begin = 1'b1;
            uop_out.tx_end = 1'b1;
        endfunction

        int enq_idx = 0; //store cracked uops into enq next. 
        generate
            for (genvar instr_idx = 0; instr_idx < SUPER_SCALAR_WIDTH; instr_idx++) begin : super_scalar_decode
                case (opcode[instr_idx])
                    // Data Transfer
                    OPCODE_LDUR:
                    OPCODE_STUR:
                    OPCODE_F_LDUR:
                    OPCODE_F_STUR:
                        if (opcode[instr_idx][20:12] != 0) begin
                            decode_m_format_add(opcode[instr_idx], enq_next[enq_idx]);
                            enq_idx = enq_idx + 1;
                        end
                        decode_m_format_mem(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = opcode[instr_idx] == OPCODE_LDUR || opcode[instr_idx] == OPCODE_F_LDUR ? UOP_LOAD : UOP_STORE;
                        enq_next[enq_idx].tx_begin = opcode[instr_idx][20:12] == 0;
                        enq_next[enq_idx].tx_end = 1'b1;
                        enq_next[enq_idx].mem_read = opcode[instr_idx] == OPCODE_LDUR || opcode[instr_idx] == OPCODE_F_LDUR;
                        enq_next[enq_idx].mem_write = opcode[instr_idx] == OPCODE_STUR || opcode[instr_idx] == OPCODE_F_STUR;
                        enq_next[enq_idx].w_enable = opcode[instr_idx] == OPCODE_LDUR || opcode[instr_idx] == OPCODE_F_LDUR;
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    // Immediate moves
                    OPCODE_MOVK:
                    OPCODE_MOVZ:
                        decode_i1_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = opcode[instr_idx] == OPCODE_MOVK ? OPCODE_MOVK : OPCODE_MOVZ;
                        enq_next[enq_idx].hw = opcode[instr_idx] == OPCODE_MOVK ? opcode[instr_idx][22:21] : 2'b0;
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_ADRP:
                        decode_i2_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    // Integer ALU operations
                    OPCODE_ADD:
                        decode_ri_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_ADD;
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_ADDS:
                        ecode_rr_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_ADD;
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_CMN:
                        decode_rr_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_ADD;
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_next[enq_idx].dst.gpr = 5'h1f; // we discard the destination even though dst could? be non 0
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_SUB:
                        decode_ri_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_SUB;
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_SUBS:
                    OPCODE_CMP:
                        ecode_rr_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_SUB; //the dst is all 1s unlike cmn.
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_MVN:
                        ecode_rr_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_MVN;
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_ORR:
                        ecode_rr_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_ORR;
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_EOR:
                        ecode_rr_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_EOR;
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_ANDS:
                    OPCODE_TST:
                        ecode_rr_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_AND;
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_LSL:
                    OPCODE_LSR:
                    OPCODE_UBFM:
                        decode_ri_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_UBFM;
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_ASR:
                        decode_ri_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_ASR;
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_idx = enq_idx + 1;
                        break;
                    // Branching
                    OPCODE_B:
                        //this has no impact on the architectural state after fetch / predecode
                        break;
                    OPCODE_B_COND:
                        enq_next[enq_idx].uop_code = UOP_BCOND;
                        enq_next[enq_idx].data = branch_data[instr_idx]; // matches the uop_branch struct
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_next[enq_idx].valb_sel = '0;
                        enq_next[enq_idx].tx_begin = 1'b1;
                        enq_next[enq_idx].tx_end = 1'b1;
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_BL:
                        enq_next[enq_idx].uop_code = UOP_BL;
                        enq_next[enq_idx].data = branch_data[instr_idx]; //the branch target and the lower 5 bits are the register to store to (X30)
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_next[enq_idx].valb_sel = '0;
                        enq_next[enq_idx].tx_begin = 1'b1;
                        enq_next[enq_idx].tx_end = 1'b1;
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_RET:
                        enq_next[enq_idx].uop_code = UOP_CHECK_RET;
                        enq_next[enq_idx].data = branch_data[instr_idx]; // the bottom 5 bits contain the register to return from
                        enq_next[enq_idx].pc = pc[instr_idx];
                        enq_next[enq_idx].valb_sel = '0;
                        enq_next[enq_idx].tx_begin = 1'b1;
                        enq_next[enq_idx].tx_end = 1'b1;
                        enq_idx = enq_idx + 1;
                        break;
                    // Misc
                    OPCODE_NOP:
                        break;
                    OPCODE_HLT:
                        enq_next[enq_idx].uop_code = UOP_HLT;
                        enq_next[enq_idx].tx_begin = 1'b1;
                        enq_next[enq_idx].tx_end = 1'b1;
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_FMOV:
                        decode_rr_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_FMOV; 
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_FNEG:
                        decode_rr_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_FNEG;
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_FADD:
                        decode_rr_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_FADD;
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_FMUL:
                        decode_rr_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_FMUL;
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_FSUB:
                    OPCODE_FCMPR:
                        decode_rr_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_FSUB; 
                        enq_idx = enq_idx + 1;
                        break;
                    OPCODE_FCMPI:
                        decode_ri_format(opcode[instr_idx], enq_next[enq_idx]);
                        enq_next[enq_idx].uop_code = UOP_FSUB; 
                        enq_idx = enq_idx + 1;
                        break;
                    default: begin
                        // oops?
                    end
                endcase
            end
        endgenerate
        enq_width = enq_idx;
    end

endmodule