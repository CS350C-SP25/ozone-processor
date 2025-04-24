`include "../../util/uop_pkg.sv"
`include "../packages/rob_pkg.sv"
`include "../registers/reg_file.sv"

import rob_pkg::*;
import reg_pkg::*;
import uop_pkg::*;

module reg_file_tb;

    // import reg_pkg::*;

    // Clock and reset
    logic clk;
    logic rst;

    // Parameters
    localparam int NUM_READ_PORTS  = 4;
    localparam int NUM_WRITE_PORTS = 2;

    // DUT I/O
    logic [NUM_READ_PORTS-1:0] read_en         ;
    logic [$clog2(NUM_PHYS_REGS)-1:0] read_index [NUM_READ_PORTS];
    logic [WORD_SIZE-1:0] read_data   [NUM_READ_PORTS];

    RegFileWritePort [NUM_WRITE_PORTS-1:0] write_ports;
    NZCVWritePort nzcv_write_port;

    // Clock generation
    always #5 clk = ~clk;

    // Instantiate DUT
    reg_file #(
        .NUM_READ_PORTS(NUM_READ_PORTS),
        .NUM_WRITE_PORTS(NUM_WRITE_PORTS)
    ) dut (
        .clk(clk),
        .rst(rst),
        .read_en(read_en),
        .read_index(read_index),
        .read_data(read_data),
        .write_ports(write_ports),
        .nzcv_write_port(nzcv_write_port)
    );

    // Test procedure
    initial begin
        $display("===== Register File Test Start =====");

        // Initial values
        clk = 0;
        rst = 1;

        // Clear control signals
        foreach (read_en[i])         read_en[i] = 0;
        foreach (read_index[i])      read_index[i] = '0;
        foreach (write_ports[i]) begin
            write_ports[i].en       = 0;
            write_ports[i].index_in = '0;
            write_ports[i].data_in  = '0;
        end

        // Apply reset
        #10;
        rst = 0;

        // --------------------
        // WRITE TEST
        // --------------------
        // Write 64'hDEADBEEF to register 5
        write_ports[0].en       = 1;
        write_ports[0].index_in = 5;
        write_ports[0].data_in  = 64'hDEADBEEF;

        // Write 64'hCAFEBABE to register 10
        write_ports[1].en       = 1;
        write_ports[1].index_in = 10;
        write_ports[1].data_in  = 64'hCAFEBABE;

        #10; // Wait one clock edge

        // Disable writes
        write_ports[0].en = 0;
        write_ports[1].en = 0;

        // --------------------
        // READ TEST
        // --------------------
        read_en[0]     = 1;
        read_index[0]  = 5;
        read_en[1]     = 1;
        read_index[1]  = 10;
        read_en[2]     = 1;
        read_index[2]  = 0; // Should be 0
        read_en[3]     = 0; // Disabled read

        #1; // Wait a tiny bit for combinational reads

        assert(read_data[0] == 64'hDEADBEEF) else $fatal("Read from reg 5 failed!");
        assert(read_data[1] == 64'hCAFEBABE) else $fatal("Read from reg 10 failed!");
        assert(read_data[2] == 0) else $fatal("Expected reg 0 to be 0 after reset!");
        assert(read_data[3] == 0) else $fatal("Read port 3 should output 0 when disabled!");

        $display("All tests passed.");
        $finish;
    end

endmodule
