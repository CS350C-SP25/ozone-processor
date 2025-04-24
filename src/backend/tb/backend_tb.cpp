#include "Vbackend.h"
#include "verilated.h"
#include "verilated_vcd_c.h"  // Optional for waveform tracing
#include <iostream>
#include <cassert>

vluint64_t main_time = 0;  // Current simulation time
double sc_time_stamp() { return main_time; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vbackend* top = new Vbackend;
    VerilatedVcdC* tfp = new VerilatedVcdC;

    Verilated::traceEverOn(true);
    top->trace(tfp, 99);
    tfp->open("backend.vcd");

    // Reset sequence
    top->clk_in = 0;
    top->rst_N_in = 0;

    for (int i = 0; i < 10; i++) {
        top->clk_in = !top->clk_in;
        top->eval();
        tfp->dump(main_time++);
    }

    top->rst_N_in = 1;

    // Drive 1 valid uop into instr_queue[0]
    top->instr_queue[0].valid = 1;
    top->instr_queue[0].uop_code = 0x01;        // Assume 0x01 = UOP_ADD
    top->instr_queue[0].pc = 0x1000;
    top->instr_queue[0].data.imm = 0x0;         // Immediate (if any)
    top->instr_queue[0].r1_arch = 5;            // src1 arch reg
    top->instr_queue[0].r2_arch = 6;            // src2 arch reg
    top->instr_queue[0].dest_arch = 10;         // dest arch reg
    top->instr_queue[0].nzcv_arch = 31;         // condition flags (NZCV)

    // Make sure only instr_queue[0] is valid
    for (int i = 1; i < 4; ++i) {
        top->instr_queue[i].valid = 0;
    }

    // Main simulation loop
    for (int cycle = 0; cycle < 1000; ++cycle) {
        top->clk_in = !top->clk_in;
        top->eval();

        // You can insert stimulus to instr_queue or other inputs here
        // E.g., populate top->instr_queue[0].uop_code = ...;
        // Set inputs or check outputs
        // Inserted after reset and before main loop
        if (top->alu_wb_out.valid) {
            std::cout << "ALU wrote back: " << std::hex << top->alu_wb_out.data << std::endl;
        }

        tfp->dump(main_time++);

        if (Verilated::gotFinish()) break;
    }

    tfp->close();
    delete tfp;
    delete top;
    return 0;
}
