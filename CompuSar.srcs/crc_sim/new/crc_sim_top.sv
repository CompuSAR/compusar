`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/09/2026 07:21:52 PM
// Design Name: 
// Module Name: crc_sim_top
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


module crc_sim_top(
    );

logic clock;

initial begin
    clock = 1'b0;
    forever begin
        #20 clock = 1'b1;
        #20 clock = 1'b0;
    end
end

logic reset=1'b0, valid7=1'b0, valid16=1'b0, value;
logic [6:0] current_crc7;
logic [15:0] current_crc16;

crc#(
    .CRC_BITS(7),
    .INIT_VALUE(7'b0),
    .POLYNOM(7'b0001001)
) crc7(
    .clock_i(clock),
    .reset_i(reset),
    .bit_valid_i(valid7),
    .bit_i(value),

    .crc_o(current_crc7)
);

crc#(
    .CRC_BITS(16),
    .INIT_VALUE(7'b0),
    .POLYNOM(16'b0001000000100001)
) crc16(
    .clock_i(clock),
    .reset_i(reset),
    .bit_valid_i(valid16),
    .bit_i(value),

    .crc_o(current_crc16)
);

// These sample calculations are from the SD simplified specs
//logic [39:0] test_value = 40'b0100000000000000000000000000000000000000; // CRC should be 1001010
//logic [39:0] test_value = 40'b0101000100000000000000000000000000000000; // CRC should be 0101010
logic [39:0] test_value = 40'b0001000100000000000000000000100100000000; // CRC should be 0110011

initial begin
    reset = 1'b1;
    valid7 = 1'b0;

    @(posedge clock);
    @(posedge clock);

    reset = 1'b0;

    @(posedge clock);
    @(posedge clock);

    for( int i=0; i<40; ++i ) begin
        @(negedge clock);
        valid7 = 1'b1;
        value = test_value[39-i];
    end

    @(negedge clock) valid7 = 1'b0;

    @(posedge clock);
    @(posedge clock);
    reset = 1'b1;
    @(posedge clock);
    @(posedge clock);
    @(posedge clock);
    reset = 1'b0;
    @(posedge clock);

    for( int i=0; i<512*8; ++i ) begin
        @(negedge clock);
        valid16 = 1'b1;
        value = 1'b1;
    end
    @(negedge clock) valid16 = 1'b0;

    // According to the SD specs, CRC should be 16'h7fa1;
end

endmodule
