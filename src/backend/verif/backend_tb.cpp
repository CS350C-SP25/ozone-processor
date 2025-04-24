#include "Vbackend_tb.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vbackend_tb* top = new Vbackend_tb;
    VerilatedVcdC* tfp = new VerilatedVcdC;

    Verilated::traceEverOn(true);
    top->trace(tfp, 99);
    tfp->open("backend.vcd");

    // Initialize
    top->clk_in = 0;
    top->rst_N_in = 0;

    // Apply reset
    for (int i = 0; i < 4; ++i) {
        top->clk_in = !top->clk_in;
        top->eval();
        tfp->dump(main_time++);
    }
    top->rst_N_in = 1;

    // Provide values for instruction inputs (passed into instr_queue[0] by backend_tb logic)
    top->uopcode = 0x10; // UOP_ADD
    top->dst_ri = 10;
    top->src_ri = 5;
    top->imm_ri = 0;
    top->hw_ri = 0;
    top->set_nzcv_ri = 0;
    top->valb_sel = 0;
    top->pc = 0x1000;

    // Simulate
    for (int i = 0; i < 100; ++i) {
        top->clk_in = !top->clk_in;
        top->eval();

        // Check ALU output from backend (if exposed in backend_tb.v)
        // e.g., top->backend_inst__DOT__alu_wb_out__valid
        // NOTE: You must `expose` internal backend signals through output ports in backend_tb.sv to access them here
        tfp->dump(main_time++);

        if (Verilated::gotFinish()) break;
    }

    tfp->close();
    delete tfp;
    delete top;

    return 0;
}
