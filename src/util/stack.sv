module stack #(
    parameter STACK_DEPTH = 8,
    parameter ENTRY_SIZE = 64
) (
    input logic clk_in,
    input logic rst_N_in,
    input logic push,
    input logic pop,
    input logic [ENTRY_SIZE-1:0] pushee,
    input logic restoreTail,
    input logic[$clog2(STACK_DEPTH)-1:0] newTail,
    output logic [ENTRY_SIZE-1:0] stack_out
);
    logic [ENTRY_SIZE-1:0] underlying [STACK_DEPTH-1:0];
    logic [ENTRY_SIZE-1:0] next_push;
    logic[$clog2(STACK_DEPTH)-1:0] tail;

    logic[$clog2(STACK_DEPTH)-1:0] tail_next;

    always_ff @(posedge clk_in) begin
        if (rst_N_in) begin
            tail <= tail_next;
            underlying[tail] <= next_push;
        end else begin
            tail <= '0;
        end
    end

    always_comb begin

        if (restoreTail) begin
            tail_next = newTail;
            next_push = underlying[tail];
        end else begin
            if (push && pop) begin
                tail_next = tail;
                next_push = pushee;
            end else if (push) begin
                tail_next = tail + 1;
                next_push = pushee;
            end else if (pop) begin
                tail_next = tail - 1;
                next_push = underlying[tail];
            end else begin
                tail_next = tail;
                next_push = underlying[tail];
            end
        end
    end

    assign stack_out = underlying[tail];

endmodule
