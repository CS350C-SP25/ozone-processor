`timescale 1ns / 1ps
`include "../frontend/frontend.sv"
`include "../backend/backend.sv"

module ozone_tb;

interface connector();
    // Shared between Backend & Frontend
    uop_insn insn_queue [`INSN_Q_DEPTH];
    logic [$clog2(`INSN_Q_DEPTH)-1:0] head;
    logic [$clog2(`INSN_Q_DEPTH)-1:0] tail;
    // Backend -> Frontend
    logic halt;
    logic mispred_branch;
    logic [63:0] branch_target;
endinterface

// Instantiate the frontend


// Instantiate the backend



endmodule