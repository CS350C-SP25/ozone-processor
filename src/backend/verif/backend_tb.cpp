#include "Vbackend_tb.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

void tick(Vbackend_tb* top, VerilatedVcdC* tfp) {
    top->clk_in = !top->clk_in;
    top->eval();
    tfp->dump(main_time++);
}
void reset(Vbackend_tb* top, VerilatedVcdC* tfp) {
    top->rst_N_in = 0;
    for (int i = 0; i < 4; ++i) {
        tick(top, tfp);
    }
    top->rst_N_in = 1;
}
void set_instr(Vbackend_tb* top, VerilatedVcdC* tfp, uint8_t uopcode, uint8_t dst_ri, uint8_t src_ri, uint32_t imm_ri, uint8_t hw_ri, uint8_t set_nzcv_ri, uint8_t valb_sel, uint32_t pc) {
    top->uopcode = uopcode;
    top->dst_ri = dst_ri;
    top->src_ri = src_ri;
    top->imm_ri = imm_ri;
    top->hw_ri = hw_ri;
    top->set_nzcv_ri = set_nzcv_ri;
    top->valb_sel = valb_sel;
    top->pc = pc;
    // wait a full clockcycle for the instruction to be processed
    for (int i = 0; i < 2; i++) {
        tick(top, tfp);
    }
}

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
    set_instr(top, tfp, 0xC, 1, 0, 0xF, 0, 0, 0, 0x1000); // MVZ x1 0xF 0
    set_instr(top, tfp, 0x2, 2, 1, 0xF, 0, 0, 0, 0x1000); // ADD x2 x1 0xF (should be 0x1E)
    set_instr(top, tfp, 0x15, 0, 0, 0, 0, 0, 0, 0x1000); // HLT

    // Simulate
    for (int i = 0; i < 20; ++i) {
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
