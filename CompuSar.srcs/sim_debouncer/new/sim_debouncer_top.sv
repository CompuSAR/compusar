`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/05/2026 05:01:12 AM
// Design Name: 
// Module Name: sim_debouncer_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module sim_debouncer_top(

    );

logic clock = 1'b0;

initial begin
    forever begin
        #0.5 clock=1'b1;
        #0.5 clock=1'b0;
    end
end

logic sigin, sigout;

debouncer#(.DEBOUNCE_CYCLES(75000), .DEFAULT_OUT(1'b1)) sd_card_detect_debouncer(
    .clock_i(clock),
    .signal_i(sigin),
    .signal_o(sigout)
);

initial begin
    sigin = 1'b0;
    #100000 sigin = 1'b1;
end

endmodule
