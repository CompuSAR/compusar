`timescale 1ns / 1ps

module debouncer#(
    parameter DEBOUNCE_CYCLES = 10000,
    parameter DEFAULT_OUT = 1'b0,
    parameter LATENCY = 3
)(
    input clock_i,
    input signal_i,

    output logic signal_o = DEFAULT_OUT
);

logic in_signal;

input_delay#(.NUM_BITS(1), .LATENCY(LATENCY)) input_delay( .clock_i(clock_i), .in(signal_i), .out(in_signal));

localparam COUNTER_BITS = $clog2(DEBOUNCE_CYCLES);
localparam COUNTER_ZERO = { COUNTER_BITS{1'b0} };
logic [COUNTER_BITS-1:0] counter = DEBOUNCE_CYCLES - 1;

always_ff@(posedge clock_i) begin
    if( in_signal == signal_o ) begin
        counter <= DEBOUNCE_CYCLES - 1;
    end else begin
        if( counter == COUNTER_ZERO )
            signal_o <= in_signal;
        else
            counter <= counter - 1;
    end
end

endmodule
