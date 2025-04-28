`include "../backend.sv"
`include "../packages/rob_pkg.sv"

module backend_tb(
    input logic clk_in,
    input logic rst_N_in,
    input uop_pkg::uop_code uopcode,
    input logic [63:0] pc,
    input logic valb_sel,
    input logic [4:0] dst_ri,
    input logic [4:0] src_ri,
    input logic [20:0] imm_ri,
    input logic [1:0] hw_ri,
    input logic set_nzcv_ri
);

    import uop_pkg::*;

    // Define the instruction queue
    uop_insn [INSTR_Q_WIDTH-1:0] instr_queue;
    logic [$bits(uop_branch)-1:0] packed_data;
    uop_ri ri;

    // Combinationally populate the instruction queue
    always_comb begin
        // Fill first instruction based on inputs
        ri.dst = '{gpr: dst_ri, is_sp: 0, is_fp: 0};
        ri.src = '{gpr: src_ri, is_sp: 0, is_fp: 0};
        ri.imm = imm_ri;
        ri.hw = hw_ri;
        ri.set_nzcv = set_nzcv_ri;
        set_data_ri(ri, packed_data);

        instr_queue[0] = '{
            uopcode: uopcode,
            data: packed_data,
            pc: pc,
            valb_sel: valb_sel,
            mem_read: 0,
            mem_write: 0,
            w_enable: 1,
            tx_begin: 0,
            tx_end: 0,
            valid: 1
        };

        // Fill remaining instructions with UOP_HLT
        for (int i = 1; i < INSTR_Q_WIDTH; ++i) begin
            instr_queue[i] = '{
                uopcode: UOP_HLT,
                data: '0,
                pc: '0,
                valb_sel: 0,
                mem_read: 0,
                mem_write: 0,
                w_enable: 0,
                tx_begin: 0,
                tx_end: 0,
                valid: 1
            };
        end
    end

    // Instantiate backend
    backend backend_inst (
        .clk_in(clk_in),
        .rst_N_in(rst_N_in),
        .instr_queue(instr_queue),
        .bcond_resolved_out(),
        .pc_incorrect_out(), 
        .taken_out(),  
        .pc_out(), 
        .correction_offset_out()
    );

endmodule
