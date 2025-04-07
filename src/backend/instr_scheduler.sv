import uop_pkg::*;
import reg_pkg::*;
import is_pkg::*;

module is_queue #(
    parameter N = IS_ENTIRES
) (
    input logic rst_N_in,
    input logic clk_in,
    input logic flush_in
    // TODO ...
);
    // instruction scheduler queue
    is_entry [N-1:0] q;
    logic [$clog2(N)-1:0] is_head;
    logic [$clog2(N)-1:0] is_tail;

    
endmodule


module ready_queue #(
    paramater N = RQ_ENTRIES
) (
    input logic rst_N_in,
    input logic clk_in,
    input logic flush_in
);
    // ready queue
    rq_entry [N-1:0] q;
    logic [$clog2(N)-1:0] rq_head;
    logic [$clog2(N)-1:0] rq_tail;

endmodule


module instruction_scheduler #() (

);

endmodule;
