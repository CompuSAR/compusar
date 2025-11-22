`timescale 1ns / 1ps

module byte_selector#(
        NUM_BYTES = 4
    )(
        input [NUM_BYTES-1:0]                   mask,
        input [NUM_BYTES*8-1:0]                 included,
        input [NUM_BYTES*8-1:0]                 complement,

        output [NUM_BYTES*8-1:0]                result
    );

genvar i;
generate
    for(i=0; i<NUM_BYTES; ++i) begin
        assign result[(i+1)*8-1:i*8] = mask[i] ? included[(i+1)*8-1:i*8] : complement[(i+1)*8-1:i*8];
    end
endgenerate

endmodule