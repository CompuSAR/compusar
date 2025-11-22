`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/16/2025 08:21:01 PM
// Design Name: 
// Module Name: seg_display
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


module seg_display#(
    parameter FREQ_DIV = 10,
    parameter NUM_DIGITS = 8,
    parameter SEG_ACTIVE_LOW = 0,
    parameter ENABLE_ACTIVE_LOW = 1
)(
    input clock_i,

    input [NUM_DIGITS*4-1:0] data_i,
    input [$clog2(NUM_DIGITS)-1:0] point_i,

    output logic [7:0] segments_o,
    output logic [NUM_DIGITS-1:0] enable_o = 0
);

// Clock divider code
localparam DIV_COUNTER_ZERO = {1'b0{$clog2(FREQ_DIV)}};
logic [$clog2(FREQ_DIV)-1:0] div_counter = DIV_COUNTER_ZERO;
wire action_cycle = div_counter == DIV_COUNTER_ZERO;

always_ff@(posedge clock_i) begin
    if( div_counter==DIV_COUNTER_ZERO ) begin
        div_counter <= FREQ_DIV-2;
    end else begin
        div_counter <= div_counter-1;
    end
end

// Determine current digit
localparam CURRENT_DIGIT_ZERO = {1'b0{$clog2(NUM_DIGITS)}};
logic [$clog2(NUM_DIGITS)-1:0] current_digit = CURRENT_DIGIT_ZERO;

always_ff@(posedge clock_i) begin
    if( action_cycle ) begin
        if( current_digit==CURRENT_DIGIT_ZERO ) begin
            current_digit <= NUM_DIGITS-1;
        end else begin
            current_digit <= current_digit-1;
        end
    end
end

wire [NUM_DIGITS*4-1:0] masked_data;
wire [3:0] current_input = masked_data[NUM_DIGITS*4-1:NUM_DIGITS*4-4];
wire [NUM_DIGITS-1:0] interim_enable;

genvar i;

generate

assign masked_data[3:0] = (current_digit==CURRENT_DIGIT_ZERO) ? data_i[3:0] : 4'b0000;

for(i=1; i<NUM_DIGITS; ++i) begin
    assign masked_data[i*4+3:i*4] =
        (i==current_digit) ?
        data_i[i*4+3:i*4] :
        masked_data[i*4-1:i*4-4];
end

for(i=0; i<NUM_DIGITS; ++i) begin
    assign interim_enable[i] = (i==current_digit ? 1'b1 : 1'b0) ^ ENABLE_ACTIVE_LOW;
    assign segments_o[0] = SEG_ACTIVE_LOW;
end

endgenerate

localparam SEGMENT_XOR = SEG_ACTIVE_LOW ? 7'b1111111 : 7'b0000000;

always_ff@(posedge clock_i) begin
    case(current_input)
        4'h0: segments_o[7:1] <= 7'b1111110 ^ SEGMENT_XOR;
        4'h1: segments_o[7:1] <= 7'b0110000 ^ SEGMENT_XOR;
        4'h2: segments_o[7:1] <= 7'b1101101 ^ SEGMENT_XOR;
        4'h3: segments_o[7:1] <= 7'b1111001 ^ SEGMENT_XOR;
        4'h4: segments_o[7:1] <= 7'b0110011 ^ SEGMENT_XOR;
        4'h5: segments_o[7:1] <= 7'b1011011 ^ SEGMENT_XOR;
        4'h6: segments_o[7:1] <= 7'b1011111 ^ SEGMENT_XOR;
        4'h7: segments_o[7:1] <= 7'b1110000 ^ SEGMENT_XOR;
        4'h8: segments_o[7:1] <= 7'b1111111 ^ SEGMENT_XOR;
        4'h9: segments_o[7:1] <= 7'b1111011 ^ SEGMENT_XOR;
        4'ha: segments_o[7:1] <= 7'b1110111 ^ SEGMENT_XOR;
        4'hb: segments_o[7:1] <= 7'b0011111 ^ SEGMENT_XOR;
        4'hc: segments_o[7:1] <= 7'b1001110 ^ SEGMENT_XOR;
        4'hd: segments_o[7:1] <= 7'b0111101 ^ SEGMENT_XOR;
        4'he: segments_o[7:1] <= 7'b1001111 ^ SEGMENT_XOR;
        4'hf: segments_o[7:1] <= 7'b1000111 ^ SEGMENT_XOR;
    endcase

    enable_o <= interim_enable;
end

endmodule
