`timescale 1ns/1ps

package reg_pkg;
    // Design parameters
    parameter int NUM_ARCH_REGS = 32;
    parameter int ADDR_BITS      = 64;
    parameter int NUM_PHYS_REGS  = 128;
    parameter int WORD_SIZE      = 64;

    // Write port structure for the register file
    typedef struct packed {
        // Which physical register to write to?
        logic [$clog2(NUM_PHYS_REGS)-1:0] index_in;
        // Write enable signal
        logic en;
        // Data input to be written
        logic [WORD_SIZE-1:0] data_in;
    } RegFileWritePort;
endpackage

