`include "../../util/uop_pkg.sv"
`include "../packages/rob_pkg.sv"
`include "../registers/rrat.sv"

import rob_pkg::*;
import reg_pkg::*;
import uop_pkg::*;

module reg_file_tb;
    logic clk;
    logic rst;

    always #5 clk = ~clk;

    // instantiate DUT
    
endmodule