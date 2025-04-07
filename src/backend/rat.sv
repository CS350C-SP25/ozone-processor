`include "rob_pkg.sv"

import rob_pkg::*;

package renaming;

endpackage
// ASSUME implementing w/ 

module rat #(
    parameter a = 1
)
(
    output rob_entry[1:0] etr
);

rob_entry[1:0] outputs;

//outputs[0].dest_reg_arch = 




endmodule