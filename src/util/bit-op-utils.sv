import op_pkg::*;

// Lookup table given an instruction
// module istable (
//     input logic [31:0] instruction,
//     output opcode_t op
// );
//     casez (instruction[31-:11])
//         11'b11111000010: // LOAD
//             assign op = OPCODE_LDUR;
//             break;
//         11'b11111000000: // STORE
//             assign op = OPCODE_STUR;
//             break;
//         11'b111100101??: // MOVK
//             assign op = OPCODE_MOVK;
//             break;
//         11'b110100101??: //MOVZ
//             assign op = OPCODE_MOVZ;
//             break;
//         11'b1??10000????: //ADRP
//             assign op = OPCODE_ADRP;
//             break;
//         11'b1001000100?: // ADD
//             assign op = OPCODE_ADD;
//             break;
//         11'b10101011000: // ADDS / CMN
//             assign op = &instruction[4:0] ? OPCODE_CMN : OPCODE_ADDS;
//             break;
//         11'b1101000100?: // SUB
//             assign op = OPCODE_SUB;
//         11'b11101011000: //SUBS / CMP
//             assign op = &instruction[4:0] ? OPCODE_CMP : OPCODE_SUBS;
//             break;
//         11'b10101010001: // MVN
//             assign op = OPCODE_MVN;
//             break;
//         11'b10101010000: // ORR
//             assign op = OPCODE_ORR;
//             break;
//         11'b11001010000: // EOR
//             assign op = OPCODE_EOR;
//             break;
//         11'b11101010000: // ANDS / TST
//             assign op = &instruction[4:0] ? OPCODE_TST : OPCODE_ANDS;
//             break;
//         11'b1101001101?: // LSL LSR UBFM
//             assign op = &instruction[15:10] ? OPCODE_LSR : (instruction[15:10] + 6'h01 == instruction[21:16]) ? OPCODE_LSL ? OPCODE_UBFM;
//             break;
//         11'b1001001101?: // ASR
//             assign op = OPCODE_ASR;
//             break;
//         11'b000101?????: // B
//             assign op = OPCODE_B;
//             break;
//         11'b01010100???: // B COND
//             assign op = OPCODE_B_COND;
//             break;
//         11'b100101?????: // BL
//             assign op = OPCODE_BL;
//             break;
//         11'b11010110010: // RET
//             assign op = OPCODE_RET;
//             break;
//         11'b11010101000: // NOP
//             assign op = OPCODE_NOP;
//             break;
//         11'b11010100010: // HLT
//             assign op = OPCODE_HLT;
//             break;
//         11'b11111100010: // FLDUR
//             assign op = OPCODE_F_LDUR;
//             break;
//         11'b11111100000: // FSTUR
//             assign op = OPCODE_F_STUR;
//             break;
//         11'b00011110011: // FMOV - FCMP
//             assign op = instruction[15-:6] == 6'b010000 ? (!|instruction[20-:5] ? OPCODE_FMOV : instruction[20-:5] == 5'b00001 ? OPCODE_FNEG : OPCODE_ERROR) : 
//                 instruction[15-:6] == 6'b001000 ? (!|instruction[20-:5] && instruction[4:0] == 5'b01000 ? OPCODE_FCMP : !|instruction[4:0] ? OPCODE_FCMPR : OPCODE_ERROR) :
//                 instruction[15-:6] == 6'b001110 ? OPCODE_FSUB : instruction[15-:6] == 6'b000010 ? OPCODE_FMUL : instruction[15-:6] == 6'b001010 ? OPCODE_FADD : OPCODE_ERROR;
//             break;
//         default: 
//             assign op = OPCODE_ERROR;
//             break;
//     endcase
// endmodule