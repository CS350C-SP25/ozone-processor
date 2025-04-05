package op_pkg;

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

endpackage
