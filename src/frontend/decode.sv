`ifndef DECODE
`define DECODE 

`include "../util/uop_pkg.sv"
`include "../util/op_pkg.sv"
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
    input instruction_array fetched_ops,
    input branch_data_array branch_data,
    input logic [63:0] pc,
    input logic fetch_valid, //how many instructions from fetch are valid TODO implement this change
    input logic exe_ready,
    output logic decode_ready,
    output uop_insn instruction_queue_in[INSTR_Q_WIDTH-1:0]
);
  uop_insn enq_next[INSTR_Q_WIDTH-1:0];

  uop_insn buffer[INSTR_Q_WIDTH-1:0];
  logic buffered;

  function automatic void decode_m_format_add(input logic [INSTRUCTION_WIDTH-1:0] op_bits,
                                              output uop_insn uop_out);
    uop_ri ri;
    ri.dst.gpr = op_bits[4:0];
    ri.dst.is_sp = '0;
    ri.dst.is_fp = '0;  // if we are adding then this isnt a fop 
    ri.src.gpr = op_bits[9:5];
    ri.src.is_sp = &op_bits[9:5];
    ri.src.is_fp = '0;
    ri.imm = {12'b0, op_bits[20:12]};
    ri.set_nzcv = '0;
    set_data_ri(ri, uop_out.data);
    uop_out.valb_sel = '0;  //use imm (there is no src2)
    uop_out.mem_read = '0;
    uop_out.mem_write = '0;
    uop_out.w_enable = '1;
    uop_out.uopcode = op_bits[20] ? UOP_SUB : UOP_ADD;  //add and sub are unsigned
    uop_out.tx_begin = 1'b1;
    uop_out.tx_end = 1'b0;
  endfunction

  function automatic void decode_m_format_mem(input logic [INSTRUCTION_WIDTH-1:0] op_bits,
                                              output uop_insn uop_out);
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

  function automatic void decode_i1_format(input logic [INSTRUCTION_WIDTH-1:0] op_bits,
                                           output uop_insn uop_out);
    uop_ri ri;
    ri.dst.gpr = op_bits[4:0];
    ri.dst.is_sp = '0;
    ri.dst.is_fp = '0;
    ri.src.gpr = 5'b0;
    ri.src.is_sp = '0;
    ri.src.is_fp = '0;
    ri.imm = {5'b0, op_bits[20:5]};
    ri.hw = op_bits[22:21];
    ri.set_nzcv = '0;
    set_data_ri(ri, uop_out.data);
    uop_out.valb_sel = '0;
    uop_out.mem_read = '0;
    uop_out.mem_write = '0;
    uop_out.w_enable = '1;
    uop_out.tx_begin = 1'b1;
    uop_out.tx_end = 1'b1;
  endfunction

  function automatic void decode_i2_format(input logic [INSTRUCTION_WIDTH-1:0] op_bits,
                                           output uop_insn uop_out);
    uop_ri ri;
    ri.dst.gpr = op_bits[4:0];
    ri.dst.is_sp = '0;
    ri.dst.is_fp = '0;

    ri.src.gpr = 5'b0;
    ri.src.is_sp = '0;
    ri.src.is_fp = '0;
    ri.imm = {op_bits[23:5], op_bits[30:29]};
    ri.set_nzcv = '0;
    set_data_ri(ri, uop_out.data);
    uop_out.valb_sel = '0;
    uop_out.mem_read = '0;
    uop_out.mem_write = '0;
    uop_out.w_enable = '1;
    uop_out.tx_begin = 1'b1;
    uop_out.tx_end = 1'b1;
  endfunction

  function automatic void decode_rr_format(input logic [INSTRUCTION_WIDTH-1:0] op_bits,
                                           output uop_insn uop_out);
    uop_rr rr;
    rr.dst.gpr = istable(op_bits) == OPCODE_CMN ? 5'h1f : op_bits[4:0];
    rr.dst.is_sp = '0;
    rr.dst.is_fp = op_bits[26];
    rr.src1.gpr = op_bits[9:5];
    rr.src1.is_sp = '0;
    rr.src1.is_fp = op_bits[26];
    rr.src2.gpr = op_bits[20:16];
    rr.src2.is_sp = '0;
    rr.src2.is_fp = op_bits[26];
    set_data_rr(rr, uop_out.data);
    uop_out.valb_sel = 1'b1;
    uop_out.mem_read = '0;
    uop_out.mem_write = '0;
    uop_out.w_enable = '1;
    uop_out.tx_begin = 1'b1;
    uop_out.tx_end = 1'b1;
  endfunction

  function automatic void decode_ri_format(input logic [INSTRUCTION_WIDTH-1:0] op_bits,
                                           output uop_insn uop_out);
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

  always_ff @(posedge clk_in) begin : decode_fsm
    if (rst_N_in && !flush_in) begin
      if (fetch_valid) begin
        if (exe_ready) begin
          instruction_queue_in <= buffered ? buffer : enq_next;
          buffered <= buffered;  //this should be 0 if the fsm is working correctly 
          buffer <= enq_next;
          decode_ready <= 1'b1;
        end else begin
          buffer <= enq_next;
          buffered <= 1'b1;
          decode_ready <= 1'b0;
        end
      end else begin
        if (exe_ready) begin
          instruction_queue_in <= buffered ? buffer : enq_next;
          buffered <= '0;
          decode_ready <= '1;
        end else begin
          decode_ready <= ~buffered;
          buffered <= buffered;
        end
      end
    end else begin
      buffered <= '0;
      decode_ready <= 1'b0;

      //also reset the queue idk if this is good tho
      for (int i = 0; i < INSTR_Q_WIDTH; i++) begin
        instruction_queue_in[i] <= '{uopcode: UOP_NOP, default: '0};
        buffer[i] <= '{uopcode: UOP_NOP, default: '0};
      end
    end
  end

  logic done;
  logic [$clog2(INSTR_Q_WIDTH)-1:0] enq_idx;  //store cracked uops into enq next. 
  always_comb begin : decode_comb_logic
    done = 1'b0;
    enq_idx = 0;
    for (int i = 0; i < INSTR_Q_WIDTH; i++) begin : fill_enq_next
      enq_next[i] = '{uopcode: UOP_NOP, default: '0};
    end
    if (fetch_valid) begin
      for (
          int instr_idx = 0; instr_idx < SUPER_SCALAR_WIDTH; instr_idx++
      ) begin : super_scalar_decode
        if (!done) begin
          case (istable(
              fetched_ops[instr_idx]
          ))
            // Data Transfer
            OPCODE_LDUR, OPCODE_STUR, OPCODE_F_LDUR, OPCODE_F_STUR: begin
              if (fetched_ops[instr_idx][20:12] != 0) begin
                decode_m_format_add(fetched_ops[instr_idx], enq_next[enq_idx]);
                enq_idx = enq_idx + 1;
              end
              decode_m_format_mem((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = istable(fetched_ops[instr_idx]) == OPCODE_LDUR ||
                  istable(fetched_ops[instr_idx]) == OPCODE_F_LDUR ? UOP_LOAD : UOP_STORE;
              enq_next[enq_idx].tx_begin = fetched_ops[instr_idx][20:12] == 0;
              enq_next[enq_idx].tx_end = 1'b1;
              enq_next[enq_idx].mem_read = istable(fetched_ops[instr_idx]) == OPCODE_LDUR ||
                  istable(fetched_ops[instr_idx]) == OPCODE_F_LDUR;
              enq_next[enq_idx].mem_write = istable(fetched_ops[instr_idx]) == OPCODE_STUR ||
                  istable(fetched_ops[instr_idx]) == OPCODE_F_STUR;
              enq_next[enq_idx].w_enable = istable(fetched_ops[instr_idx]) == OPCODE_LDUR ||
                  istable(fetched_ops[instr_idx]) == OPCODE_F_LDUR;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            // Immediate moves
            OPCODE_MOVK, OPCODE_MOVZ: begin
              decode_i1_format(fetched_ops[instr_idx], enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = istable(fetched_ops[instr_idx]) == OPCODE_MOVK ?
                  UOP_MOVK : UOP_MOVZ;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_ADRP: begin
              decode_i2_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            // Integer ALU operations
            OPCODE_ADD: begin
              decode_ri_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_ADD;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_ADDS: begin
              decode_rr_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_ADD;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_CMN: begin
              decode_rr_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_ADD;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_SUB: begin
              decode_ri_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_SUB;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_SUBS, OPCODE_CMP: begin
              decode_rr_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_SUB;  //the dst is all 1s unlike cmn.
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_MVN: begin
              decode_rr_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_MVN;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_ORR: begin
              decode_rr_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_ORR;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_EOR: begin
              decode_rr_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_EOR;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_ANDS, OPCODE_TST: begin
              decode_rr_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_AND;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_LSL, OPCODE_LSR, OPCODE_UBFM: begin
              decode_ri_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_UBFM;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_ASR: begin
              decode_ri_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_ASR;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            // Branching
            OPCODE_B: begin
              done = 1'b1;
              //this has no impact on the architectural state after fetch / predecode
            end
            OPCODE_B_COND: begin
              done = branch_data[instr_idx].predict_taken;
              enq_next[enq_idx].uopcode = UOP_BCOND;
              enq_next[enq_idx].data = branch_data[instr_idx];  // matches the uop_branch struct
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_next[enq_idx].valb_sel = '0;
              enq_next[enq_idx].tx_begin = 1'b1;
              enq_next[enq_idx].tx_end = 1'b1;
              enq_idx = enq_idx + 1;
            end
            OPCODE_BL: begin
              done = 1'b1;
              enq_next[enq_idx].uopcode = UOP_BL;
              enq_next[enq_idx].data = branch_data[instr_idx]; //the branch target and the lower 5 bits are the register to store to (X30)
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_next[enq_idx].valb_sel = '0;
              enq_next[enq_idx].tx_begin = 1'b1;
              enq_next[enq_idx].tx_end = 1'b1;
              enq_idx = enq_idx + 1;
            end
            OPCODE_RET: begin
              done = 1'b1;
              enq_next[enq_idx].uopcode = UOP_CHECK_RET;
              enq_next[enq_idx].data = branch_data[instr_idx]; // the bottom 5 bits contain the register to return from
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_next[enq_idx].valb_sel = '0;
              enq_next[enq_idx].tx_begin = 1'b1;
              enq_next[enq_idx].tx_end = 1'b1;
              enq_idx = enq_idx + 1;
              break;
            end
            OPCODE_NOP: begin
            end
            OPCODE_HLT: begin
              enq_next[enq_idx].uopcode = UOP_HLT;
              enq_next[enq_idx].tx_begin = 1'b1;
              enq_next[enq_idx].tx_end = 1'b1;
              enq_idx = enq_idx + 1;
            end
            OPCODE_FMOV: begin
              decode_rr_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_FMOV;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_FNEG: begin
              decode_rr_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_FNEG;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_FADD: begin
              decode_rr_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_FADD;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_FMUL: begin
              decode_rr_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_FMUL;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_FSUB, OPCODE_FCMPR: begin
              decode_rr_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_FSUB;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            OPCODE_FCMPI: begin
              decode_ri_format((fetched_ops[instr_idx]), enq_next[enq_idx]);
              enq_next[enq_idx].uopcode = UOP_FSUB;
              enq_next[enq_idx].pc = pc + 64'(instr_idx << 2);
              enq_idx = enq_idx + 1;
            end
            default: begin
            end
          endcase
        end
        $display("fetched_ops: %x", fetched_ops);
        //debug
        if (enq_idx > 0) begin
                          //  $display("[Decode] Instr %d at PC 0x%h: opcode=%s, instr=0x%h", instr_idx,
                            //     enq_next[enq_idx-1].pc, enq_next[enq_idx-1].uopcode.name(), fetched_ops[instr_idx]);
                        end
        //                 //debug


      end
    end
  end

endmodule

`endif
