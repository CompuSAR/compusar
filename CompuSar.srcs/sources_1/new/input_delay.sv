`timescale 1ns / 1ps

module input_delay#(NUM_BITS = 1, LATENCY = 3)
(
    input clock_i,

    input [NUM_BITS-1:0]in,

    output [NUM_BITS-1:0]out
);

logic [NUM_BITS-1:0]buffer[LATENCY];

assign out = buffer[LATENCY-1];

always_ff@(posedge clock_i) begin
    int i;

    buffer[0] <= in;

    for( i=1; i<LATENCY; ++i ) begin
        buffer[i] <= buffer[i-1];
    end
end

endmodule
