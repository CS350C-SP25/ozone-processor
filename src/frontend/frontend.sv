import op_pkg::*;

// top level module of the frontend, communicates with backend's top level module through instruction queue
module frontend #(
    parameter INSTRUCTION_WIDTH = op_pkg::INSTRUCTION_WIDTH,
    parameter SUPER_SCALAR_WIDTH = op_pkg::SUPER_SCALAR_WIDTH,
) (

);

logic [SUPER_SCALAR_WIDTH-1:0][INSTRUCTION_WIDTH-1:0] fetched_ops;


endmodule