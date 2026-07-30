`timescale 1ns / 1ps

module crc# (
    CRC_BITS = 16,
    POLYNOM = 1
)(
    input clock_i,
    input reset_i,
    input bit_valid_i,
    input bit_i,
    input [CRC_BITS-1:0] init_value_i,

    output [CRC_BITS-1:0] crc_o
);

logic [CRC_BITS-1:0] crc;
wire [CRC_BITS-1:0] shifted;
assign shifted = {crc[CRC_BITS-2:0], 1'b0};

assign crc_o = crc;

always_ff@(posedge clock_i) begin
    if( reset_i ) begin
        crc <= init_value_i;
    end else if( bit_valid_i ) begin
        if( crc[CRC_BITS-1] ^ bit_i ) begin
            crc <= shifted ^ POLYNOM;
        end else begin
            crc <= shifted;
        end
    end
end

endmodule
