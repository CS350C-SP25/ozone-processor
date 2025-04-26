// Modified copy of DIMM from hdl-mem-subsystem.
// Specifically to cater to Ozone frontend testing purposes.

typedef enum {PRE, READ, READPRE, WRITE, WRITEPRE, ACTIVATE, IDLE, REFRESH} BANK_CMDS;

module dimm #(
    parameter int CAS_LATENCY = 22,  // latency in cycles to get a response from DRAM
    parameter int ACTIVATION_LATENCY = 8,  // latency in cycles to activate row buffer
    parameter int PRECHARGE_LATENCY = 5,  // latency in cycles to precharge (clear row buffer)
    parameter int ROW_BITS = 8,  // log2(ROWS)
    parameter int COL_BITS = 4,  // log2(COLS)
    parameter int WIDTH = 16,
    parameter int REFRESH_CYCLE = 5120
) (
    /* ACTUAL DIMM SIGNALS */
    // Generic
    input logic clk_in,
    input logic rst_N_in,  // reset FSMs
    input logic cs_N_in,  // chip select. active low
    // SDRAM specific inputs from memory bus
    // note: addr_in[16:15:14] = { ras_n_in, cas_n_in, we_n_in }
    input logic act_in,  // Activate dram inputs
    input logic [16:0] addr_in,  // row/col. Needs two cycles.
    input logic [1:0] bg_in,  // Bank group id
    input logic [1:0] ba_in,  // Bank id
    input logic [63:0] dqm_in,  // Data mask in. Set to one to block masks
    // InOut with SDRAM controller
    inout wire [63:0] dqs,  // Data ins / outs (from all dram chips)

    /* ADDED FOR TESTING INTERFACE, ALL THESE SIGNALS WILL BE
    IGNORED WHEN ACTUALLY SIMULATING */
    input logic we_in, // Write to DIMM from Ozone tb
    inout wire [63:0] tb_line, // Data ins / outs
    output logic dimm_valid_out, // Data on tb_line valid
    output logic dimm_ready_out // DIMM ready to write/read

);
    localparam NUM_CHIPS = 64/WIDTH;
    // Process these signals and return the correct data to the LLC
    generate
		  genvar i;
        for (i = 0; i < NUM_CHIPS; i ++) begin: chip_inst
            ddr4_sdram_chip 
            #(
                .WIDTH    (WIDTH    ),
                //.BANKS    (BANKS    ),
                .ROW_BITS (ROW_BITS ),
                .COL_BITS (COL_BITS ),
                .id(i)
            )
            u_ddr4_sdram_chip(
                .clk_in   (clk_in   ),
                .rst_N_in (rst_N_in ),
                .cs_N_in  (cs_N_in  ),
                //.cke_in   (cke_in   ),
                .act_in   (act_in   ),
                .addr_in  (addr_in  ),
                .bg_in    (bg_in    ),
                .ba_in    (ba_in    ),
                .dqm_in   (dqm_in[(i + 1) * WIDTH - 1: i * WIDTH]   ),
                .dqs      (dqs[(i + 1) * WIDTH - 1: i * WIDTH]),
                .we_in    (we_in),
                .tb_line  (tb_line[(i + 1) * WIDTH - 1: i * WIDTH]),
                .dimm_valid_out (dimm_valid_out),
                .dimm_ready_out (dimm_ready_out)
            );                

        end
    endgenerate

endmodule : ddr4_dimm

module ddr4_sdram_chip #(
    // x16 DRAM. We can read 16b from the row buffer at once, and need four chips for a full read.
    parameter int WIDTH = 16,  // bus width per chip.
    parameter int BANKS = 8,  // banks per group
    parameter int ROW_BITS = 8,  // 256 rows per bank
    parameter int COL_BITS = 4,  // 16 cols per bank
    parameter int id = 0
) (
    // Generic
    input logic clk_in,
    input logic rst_N_in,  // reset FSMs
    input logic cs_N_in,  // chip select. active low
    // SDRAM specific inputs from memory bus
    //input logic cke_in,  // Clock enable
    // note: addr_in[16:15:14] = { ras_n_in, cas_n_in, we_n_in }
    input logic act_in,  // Activate dram inputs
    input logic [16:0] addr_in,  // row/col. Needs two cycles.
    input logic [1:0] bg_in,  // Bank group id
    input logic [1:0] ba_in,  // Bank id
    input logic [WIDTH-1:0] dqm_in,  // Data mask in. Set to one to block masks
    // InOut with SDRAM controller
    inout wire [WIDTH-1:0] dqs,  // Data in / out

    /* ADDED FOR TESTING INTERFACE, ALL THESE SIGNALS WILL BE
    IGNORED WHEN ACTUALLY SIMULATING */
    input logic we_in, // Write to DIMM from Ozone tb
    inout wire [63:0] tb_line, // Data ins / outs
    output logic dimm_valid_out, // Data on tb_line valid
    output logic dimm_ready_out // DIMM ready to write/read
);

    struct {
        logic[ROW_BITS-1:0] row_idx;
        logic[COL_BITS-1:0] col_idx;
        logic command_set; // set to high for exactly one cycle when we input a command. command is contained in the command enum;
        BANK_CMDS command;
    } bank_inputs[BANKS];
    struct {
        logic [7:0][WIDTH-1:0] write_buffer;
        logic [7:0][WIDTH-1:0] mask_buffer;
    } bank_buffers[BANKS];
	 
    integer burst_count;

    generate
		  genvar i;
        for (i = 0; i < BANKS; i++) begin: bank_inst
            sdram_bank  #(.ROW_BITS(ROW_BITS), .COL_BITS(COL_BITS), .WIDTH(WIDTH), .chip_id(id),.bank_id(i))
            chip_bank
            (
                .clk_in(clk_in),
                .rst_N_in(rst_N_in),
                .row_idx(bank_inputs[i].row_idx),
                .col_idx(bank_inputs[i].col_idx),
                .selected(bank_inputs[i].command_set),
                .command(bank_inputs[i].command),
                .write_buffer('{
                    bank_buffers[i].write_buffer[7],
                    bank_buffers[i].write_buffer[6],
                    bank_buffers[i].write_buffer[5],
                    bank_buffers[i].write_buffer[4],
                    bank_buffers[i].write_buffer[3],
                    bank_buffers[i].write_buffer[2],
                    bank_buffers[i].write_buffer[1],
                    bank_buffers[i].write_buffer[0]
                }),
                .mask_buffer('{
                    bank_buffers[i].mask_buffer[7],
                    bank_buffers[i].mask_buffer[6],
                    bank_buffers[i].mask_buffer[5],
                    bank_buffers[i].mask_buffer[4],
                    bank_buffers[i].mask_buffer[3],
                    bank_buffers[i].mask_buffer[2],
                    bank_buffers[i].mask_buffer[1],
                    bank_buffers[i].mask_buffer[0]
                }),

                .dqs_out(dqs)
                .tb_line_out(tb_line)
            );
        end
    endgenerate
    

    // idle - search for ACT_n & CS_n low
    // next clock read the read/write command
    // decode address bits accordingly

    logic[2:0] bank_idx;
    assign bank_idx = $unsigned({bg_in[0], ba_in});
    logic [5:0]command_bits;
    /* ADDED FOR TESTING, WE_IN TO "CHEAT" IN DATA TO THE DIMM TO START */
    assign command_bits = we_in ? {6'b011000} : {cs_N_in, act_in, addr_in[16], addr_in[15], addr_in[14], addr_in[10]};
    logic start_burst, reset_burst;
    always_ff @ (posedge clk_in) begin
        if (!rst_N_in)
            reset_burst = 1;
        else
            reset_burst = 0;

        for (int i = 0; i < BANKS; i++) begin
            bank_inputs[i].command_set <= i == 32'(bank_idx);
        end
        // $display("CMD: %b", command_bits);

        start_burst = 0;
        casez (command_bits)
            6'b01001?:    begin 
                bank_inputs[bank_idx].command <= REFRESH; 
                //$display("[DIMM] refresh");
            end    // Refresh
            6'b010100:    begin 
                bank_inputs[bank_idx].command <= PRE;
                //$display("[DIMM] pre"); 
            end     // Single Bank Precharge
            6'b00????:    begin 
                bank_inputs[bank_idx].command <= ACTIVATE; 
                //$display("[DIMM] activating");
            end// Bank Activate (uses row index)
            6'b011000: begin
                bank_inputs[bank_idx].command <= WRITE;   // Write
                //$display("[DIMM] Writing %d %x", bank_idx, dqs);
                start_burst = 1;
            end
            6'b011001:    begin
                bank_inputs[bank_idx].command <= WRITEPRE;// Write with Auto-precharge
                start_burst = 1;
               //$display("[DIMM] Writing Pre");
            end
            6'b011010:    begin 
                bank_inputs[bank_idx].command <= READ; 
                //$display("[DIMM] Reading"); 
            end   // Read
            6'b011011:    begin 
                bank_inputs[bank_idx].command <= READPRE; 
                //$display("[DIMM] Reading Pre"); 
            end // Read with Auto-Precharge
            default: begin
                bank_inputs[bank_idx].command <= IDLE;
            end
        endcase

        if (command_bits[5:4] == 2'b00) begin
            // Bank Activate, row
            bank_inputs[bank_idx].row_idx <= ROW_BITS'(addr_in);
        end
        else begin
            bank_inputs[bank_idx].col_idx <= COL_BITS'(addr_in);
        end
    end
	 
	

    always_ff @(clk_in) begin
        if (reset_burst)
            burst_count <= 8;
        
        else if (start_burst && burst_count == 8) begin
                burst_count <= 1;
               // bank_inputs[bank_idx].write_buffer[0] <= dqs;
               // bank_inputs[bank_idx].mask_buffer[0] <= dqm_in;
            bank_buffers[bank_idx].write_buffer[0] <= dqs;
            bank_buffers[bank_idx].mask_buffer[0] <= dqm_in;
 
        end
        else if (burst_count < 8) begin
            bank_buffers[bank_idx].write_buffer[burst_count] <= dqs;
            bank_buffers[bank_idx].mask_buffer[burst_count] <= dqm_in;
            burst_count <= burst_count + 1;
        end
    end
endmodule : ddr4_sdram_chip

module sdram_bank #(
    parameter int CAS_LATENCY = 22,
    parameter int ACTIVATION_LATENCY = 8,  // latency in cycles to activate row buffer
    parameter int PRECHARGE_LATENCY = 5,  // latency in cycles to precharge (clear row buffer)    parameter int WIDTH = 16,  // bus width per chip.
    parameter int BANKS = 8,  // banks per group
    parameter int ROW_BITS = 8,  // rows per bank
    parameter int COL_BITS = 4,  // cols per bank
    parameter int WIDTH = 16,
    parameter chip_id = 0,
    parameter bank_id = 0
) (
    input logic clk_in,
    input logic rst_N_in,
    input logic[ROW_BITS-1:0] row_idx,
    input logic[COL_BITS-1:0] col_idx,
    input BANK_CMDS command,
    input logic selected,
    input logic[7:0][WIDTH-1:0] write_buffer,
    input logic[7:0][WIDTH-1:0] mask_buffer ,
    // InOut with SDRAM controller
    inout logic [WIDTH-1:0] dqs_out,  // Data ins / outs (from all dram chips)
    
);
    logic [WIDTH-1:0] bank[(1 << ROW_BITS) - 1:0][(1 << COL_BITS) - 1: 0];
    logic [ROW_BITS-1:0] active_row;
    logic row_active;
    logic awaiting_activation;
    logic awaiting_precharge;
    logic awaiting_read;
    logic awaiting_write;

    logic[31:0] cycle_counter;
    logic [WIDTH-1:0] row_buffer[(1 << COL_BITS) - 1:0];

    logic read_ready;
    logic [WIDTH-1:0] next_read;
    logic burst_write;

    logic burst_start; // updated from handler
    logic[2:0] burst_val;
    logic [2:0] burst_end;


    always_ff @(clk_in) begin
        //$display("c%d b%d adqs buf: %h", chip_id, bank_id, dqs);
        if (rst_N_in) begin
            if (selected) begin
                case (command)
                    ACTIVATE:begin
                        awaiting_activation <= 1;
                    end
                    PRE:     begin
                        awaiting_precharge <= 1;
                    end  
                    WRITE:   begin
                        awaiting_write <= 1;
                    end  
                    READ:    begin
                        awaiting_read <= 1;
                    end  
                    WRITEPRE:begin
                        awaiting_write <= 1;
                        awaiting_precharge <= 1;
                    end      
                    READPRE: begin
                        awaiting_read <= 1;
                        awaiting_precharge <= 1;
                    end      
                    REFRESH: begin
                        awaiting_activation <= 1;
                        awaiting_precharge <= 1;
                    end
                    IDLE:;
                    default: $display("INVALID STATE INSIDE BANK");
                endcase
            end
            if (cycle_counter == ((ACTIVATION_LATENCY - 1) << 1) + 1 && awaiting_activation) begin
                row_active <= 1'b1;
                row_buffer <= bank[row_idx];
                awaiting_activation <= 1'b0;
                cycle_counter <= 32'b0;
            end
            else if (burst_start) begin
                if (!burst_write) begin
                    next_read <= row_buffer[{col_idx[COL_BITS-1:3], burst_val}];
                end else begin
                    row_buffer[{col_idx[COL_BITS-1:3], burst_val}] <= (row_buffer[{col_idx[COL_BITS-1:3], burst_val}] & mask_buffer[{burst_val}]) | (write_buffer[{burst_val}] & ~mask_buffer[{burst_val}]);
                end
                burst_start <= burst_val == burst_end ? 0 : 1;
                burst_val <= burst_val  + 1;
            end
            else if (cycle_counter == ((PRECHARGE_LATENCY - 1) << 1) + 1 && awaiting_precharge && !awaiting_activation && !awaiting_read && !awaiting_write) begin
                bank[active_row] <= row_buffer;
                row_active <= 1'b0;
                awaiting_precharge <= 1'b0;
                cycle_counter <= 32'b0;
            end
            else if (cycle_counter == ((CAS_LATENCY - 2) << 1) + 1 && awaiting_write && !awaiting_activation) begin
                burst_val <= 3'b0;
                burst_end <= 3'b111;
                burst_start <= 1'b1;
                awaiting_write <= 1'b0;
                cycle_counter <= 32'b0;
                burst_write <= 1'b1;
            end
            else if (cycle_counter == ((CAS_LATENCY - 2) << 1) + 1 && awaiting_read && !awaiting_activation) begin
                burst_val <= col_idx[2:0];
                burst_end <= col_idx[2:0] + 3'b111;
                burst_start <= 1'b1;
                awaiting_read <= 1'b0;
                cycle_counter <= 32'b0;
                burst_write <= 1'b0;
            end
            else if ((awaiting_activation || awaiting_precharge || awaiting_read || awaiting_write)) begin
                cycle_counter <= cycle_counter + 32'h01;
                burst_start <= 0;
            end
        end else begin
            row_active <= 0;
            awaiting_activation <= 0;
            awaiting_precharge <= 0;
            awaiting_read <= 0;
            awaiting_write <= 0;
            burst_start <= 0;
            burst_val <= 0;
        end
    end

    assign dqs_out = (burst_start && !burst_write) ? next_read : {(WIDTH){1'bz}};
    
endmodule : sdram_bank

