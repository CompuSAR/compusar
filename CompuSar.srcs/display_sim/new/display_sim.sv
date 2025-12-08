`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/16/2025 11:50:45 AM
// Design Name: 
// Module Name: display_sim
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


module display_sim(

    );

logic clock = 1'b0;
logic reset = 1'b1;
logic uart_tx;

logic req_valid, req_ack = 1'b0, rsp_valid = 1'b0, next_ack = 1'b1;
logic [31:0] req_addr;
logic [127:0] rsp_data = 128'h000102030405060708090a0b0c0d0e0f;

initial begin
    forever begin
        #10 clock = 1'b1;
        #10 clock = 1'b0;
    end
end

initial begin
    #200 reset = 1'b0;
end

logic [127:0] memory[64*1024/16];
initial
    $readmemh("screen.mem", memory);

always_ff@(posedge clock) begin
    rsp_valid <= 1'b0;

    if( req_valid ) begin
        if( req_ack ) begin
            rsp_valid <= 1'b1;
            req_ack <= next_ack;
            next_ack <= !next_ack;

            rsp_data <= memory[req_addr[31:4]];
        end else begin
            req_ack <= 1'b1;
        end
    end
end

display d(
    .clock_i(clock),
    .reset_i(reset),

    .req_valid_o(req_valid),
    .req_addr_o(req_addr),
    .req_ack_i(req_ack),

    .rsp_valid_i(rsp_valid),
    .rsp_data_i(rsp_data),

    .uart_send_o(uart_tx)
);
endmodule
