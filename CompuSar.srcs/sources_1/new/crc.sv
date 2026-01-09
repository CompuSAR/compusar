`timescale 1ns / 1ps

module crc# (
    CRC_BITS = 16,
    INIT_VALUE = 0,
    POLYNOM = 1
)(
    input clock_i,
    input reset_i,
    input bit_valid_i,
    input bit_i,

    output [CRC_BITS-1:0] crc_o
);

logic [CRC_BITS-1:0] crc;
wire [CRC_BITS-1:0] shifted;
assign shifted = {crc[CRC_BITS-2:0], 1'b0};

assign crc_o = crc;

always_ff@(posedge clock_i) begin
    if( reset_i ) begin
        crc <= INIT_VALUE;
    end else if( bit_valid_i ) begin
        if( crc[CRC_BITS-1] ^ bit_i ) begin
            crc <= shifted ^ POLYNOM;
        end else begin
            crc <= shifted;
        end
    end
end

endmodule
