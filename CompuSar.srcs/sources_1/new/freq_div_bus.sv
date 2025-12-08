`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/25/2024 06:13:12 AM
// Design Name: 
// Module Name: freq_div_bus
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


module freq_div_bus#( COUNTER_BITS = 32 )
(
    input clock_i,
    input reset_i,

    input [15:0] ctl_div_nom_i,
    input [15:0] ctl_div_denom_i,

    input slow_cmd_valid_i,
    output slow_cmd_ready_o,

    output fast_cmd_valid_o,
    input fast_cmd_ready_i
    );

logic [COUNTER_BITS:0] counter;

assign slow_cmd_ready_o = fast_cmd_ready_i && counter[COUNTER_BITS];
assign fast_cmd_valid_o = slow_cmd_valid_i && slow_cmd_ready_o;

always_ff@(posedge clock_i, posedge reset_i)
begin
    if( reset_i ) begin
        counter <= {COUNTER_BITS+1{1'b1}};
    end else begin
        if( slow_cmd_valid_i && slow_cmd_ready_o )
            counter += ctl_div_nom_i;
        else
            counter -= ctl_div_denom_i;
    end
end

endmodule
