/** 
* This cache is meant to be completely combinational -- 0 cycle latency, but also req data to the L1 when requested.
*/

module l0_instruction_cache #(
    parameter int LINES = 8,
    parameter int LINE_SIZE = 512
) ();

  always_comb begin : l0_combinational_block

  end

endmodule
