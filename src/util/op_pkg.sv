package op_pkg;

    parameter int INSTRUCTION_WIDTH = 32;
    parameter int SUPER_SCALAR_WIDTH = 2;

    typedef enum logic[6:0] {
        // Data transfer
        OPCODE_LDUR,
        OPCODE_STUR,

        // Data processing: immediate
        OPCODE_MOVK,
        OPCODE_MOVZ,
        OPCODE_ADRP,

        // Computation (arithmetic, logical, shift)
        OPCODE_ADD,
        OPCODE_ADDS,
        OPCODE_CMN,
        OPCODE_SUB,
        OPCODE_SUBS,
        OPCODE_CMP,
        OPCODE_MVN,
        OPCODE_ORR,
        OPCODE_EOR,
        OPCODE_ANDS,
        OPCODE_TST,
        OPCODE_LSL,
        OPCODE_LSR,
        OPCODE_UBFM,
        OPCODE_ASR,

        // Control transfer
        OPCODE_B,
        OPCODE_B_COND,
        OPCODE_BL,
        OPCODE_RET,

        // Misc
        OPCODE_NOP,
        OPCODE_HLT,

        // Floating-Point
        OPCODE_F_LDUR,
        OPCODE_F_STUR,
        OPCODE_FMOV,
        OPCODE_FNEG,
        OPCODE_FADD,
        OPCODE_FMUL,
        OPCODE_FSUB,
        OPCODE_FCMPI,
        OPCODE_FCMPR,
        OPCODE_ERROR
    } opcode_t;

    // Lookup table given an instruction
    function automatic opcode_t istable (
        input logic [31:0] instruction,
    );
        casez (instruction[31-:11])
            11'b11111000010: // LOAD
                return OPCODE_LDUR;
            11'b11111000000: // STORE
                return OPCODE_STUR;
            11'b111100101??: // MOVK
                return OPCODE_MOVK;
            11'b110100101??: //MOVZ
                return OPCODE_MOVZ;
            11'b1??10000????: //ADRP
                return OPCODE_ADRP;
            11'b1001000100?: // ADD
                return OPCODE_ADD;
            11'b10101011000: // ADDS / CMN
                return &instruction[4:0] ? OPCODE_CMN : OPCODE_ADDS;
            11'b1101000100?: // SUB
                return OPCODE_SUB;
            11'b11101011000: //SUBS / CMP
                return &instruction[4:0] ? OPCODE_CMP : OPCODE_SUBS;
            11'b10101010001: // MVN
                return OPCODE_MVN;
            11'b10101010000: // ORR
                return OPCODE_ORR;
            11'b11001010000: // EOR
                return OPCODE_EOR;
            11'b11101010000: // ANDS / TST
                return &instruction[4:0] ? OPCODE_TST : OPCODE_ANDS;
            11'b1101001101?: // LSL LSR UBFM
                return &instruction[15:10] ? OPCODE_LSR : (instruction[15:10] + 6'h01 == instruction[21:16]) ? OPCODE_LSL ? OPCODE_UBFM;
            11'b1001001101?: // ASR
                return OPCODE_ASR;
            11'b000101?????: // B
                return OPCODE_B;
            11'b01010100???: // B COND
                return OPCODE_B_COND;
            11'b100101?????: // BL
                return OPCODE_BL;
            11'b11010110010: // RET
                return OPCODE_RET;
            11'b11010101000: // NOP
                return OPCODE_NOP;
            11'b11010100010: // HLT
                return OPCODE_HLT;
            11'b11111100010: // FLDUR
                return OPCODE_F_LDUR;
            11'b11111100000: // FSTUR
                return OPCODE_F_STUR;
            11'b00011110011: // FMOV - FCMP
                return instruction[15-:6] == 6'b010000 ? (!|instruction[20-:5] ? OPCODE_FMOV : instruction[20-:5] == 5'b00001 ? OPCODE_FNEG : OPCODE_ERROR) : 
                    instruction[15-:6] == 6'b001000 ? (!|instruction[20-:5] && instruction[4:0] == 5'b01000 ? OPCODE_FCMP : !|instruction[4:0] ? OPCODE_FCMPR : OPCODE_ERROR) :
                    instruction[15-:6] == 6'b001110 ? OPCODE_FSUB : instruction[15-:6] == 6'b000010 ? OPCODE_FMUL : instruction[15-:6] == 6'b001010 ? OPCODE_FADD : OPCODE_ERROR;
            default: 
                return OPCODE_ERROR;
        endcase
    endfunction

endpackage
