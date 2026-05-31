`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/27/2026 07:45:03 PM
// Design Name: 
// Module Name: dbglogger
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


module dbglogger#(
    WIDTH = 32
) (
    input clk_i,
    input rst_i,

    input [WIDTH-1:0] log_data_i,
    input log_enable_i,

    input ctrl_req_valid_i,
    input [31:0] ctrl_req_data_i,
    input [15:0] ctrl_req_addr_i,
    input ctrl_req_write_i,
    output ctrl_req_ack_o,

    output logic ctrl_rsp_valid_o = 1'b0,
    output logic [31:0] ctrl_rsp_data_o
    );

localparam Mask = 32'h00003fff;

logic [13:0]write_ptr = 0, lookup_ptr;
logic [WIDTH-1:0] lookup_data, return_data;
logic lookup_enable = 1'b0, data_ready = 1'b0;
logic active = 1'b1, looped = 1'b0;

dbglogger_ram ram(
    .clka(clk_i),
    
    .addra(write_ptr),
    .dina(log_data_i),
    .wea(1'b1),
    .ena(log_enable_i),

    .addrb(lookup_ptr),
    .doutb(lookup_data),
    .enb(lookup_enable)
);

always_ff@(posedge clk_i) begin
    data_ready <= 1'b0;

    if( log_enable_i && active && !rst_i ) begin
        write_ptr <= (write_ptr + 1) & Mask;
        if( ((write_ptr+1) & Mask) == 0 ) begin
            looped <= 1'b1;
        end
    end

    if( lookup_enable ) begin
        data_ready <= 1'b1;
    end
    
    if( data_ready ) begin
        return_data <= lookup_data;
    end
end

assign ctrl_req_ack_o = !lookup_enable;

always_ff@(posedge clk_i) begin
    lookup_enable <= 1'b0;
    ctrl_rsp_valid_o <= 1'b0;

    if( ctrl_req_valid_i && ctrl_req_ack_o ) begin
        if( ctrl_req_write_i ) begin
            case( ctrl_req_addr_i )
                16'h0000: begin
                    lookup_ptr <= ctrl_req_data_i;
                    lookup_enable <= 1'b1;
                end
            endcase
        end else begin
            ctrl_rsp_valid_o <= 1'b1;
            case( ctrl_req_addr_i )
                16'h0000: begin
                    ctrl_rsp_data_o <= write_ptr | (looped?32'h80000000:32'h0);
                    active <= 1'b0;
                end
                16'h0004: ctrl_rsp_data_o <= Mask;      // Mask
                16'h0010: ctrl_rsp_data_o <= return_data[31:0];
            endcase
        end
    end
end

endmodule
