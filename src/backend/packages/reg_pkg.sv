`ifndef REG_PKG_SV
`define REG_PKG_SV
package reg_pkg;
    parameter int NUM_ARCH_REGS = 32;
    parameter int ADDR_BITS = 64;
    parameter int NUM_PHYS_REGS = 128;
    parameter int WORD_SIZE = 64;

    typedef struct packed {
        // INS
        // which register to read from?
        logic [$clog2(NUM_PHYS_REGS) - 1: 0]    index_in;
        logic                                   en;
        // OUTS
        logic [WORD_SIZE-1:0]                   data_out;

    } RegFileReadPort;

    typedef struct packed {
        // INS
        // which register to write to?
        logic [$clog2(NUM_PHYS_REGS) - 1: 0]    index_in;
        logic                                   en;
        logic [WORD_SIZE-1:0]                   data_in;
        // OUTS
        // no outputs, can assume the write is made by the next positive clock edge
    } RegFileWritePort;

    typedef struct packed {
        logic valid;
        logic [$clog2(NUM_PHYS_REGS) - 1: 0]    index_in;
        logic [3:0] nzcv; // N Z C V
    } NZCVWritePort;
endpackage
`endif // REG_PKG_SV
