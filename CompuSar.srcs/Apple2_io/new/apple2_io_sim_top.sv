`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/09/2026 09:44:11 PM
// Design Name: 
// Module Name: apple2_io_sim_top
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


module apple2_io_sim_top

import a2_io::*;

();

logic clock = 1'b0;

initial forever begin
    #500 clock = 1'b1;
    #500 clock = 1'b0;
end

logic cpu_req_valid = 1'b0, cpu_req_ack, cpu_req_write, cpu_rsp_valid;
logic [7:0] cpu_req_data, cpu_rsp_data;
logic [15:0] cpu_req_addr;

logic perph_req_valid[NumPeripherals], perph_req_ack[NumPeripherals], perph_req_write[NumPeripherals];
logic perph_rsp_valid[NumPeripherals];
logic [7:0] perph_req_data[NumPeripherals], perph_rsp_data[NumPeripherals];
logic [15:0] perph_req_addr[NumPeripherals];


initial begin
    // CPU thread
    @(negedge clock);
    cpu_req_valid = 1'b1;
    cpu_req_addr = 16'hfffc;
    cpu_req_write = 1'b0;

    @(posedge clock);
    while( !cpu_req_ack )
        @(posedge clock);

    @(negedge clock);
    cpu_req_valid = 1'b0;
end

initial perph_req_ack[Mem] = 1'b1;

always_ff@(posedge clock) begin
    // Memory thread
    perph_rsp_valid[Mem] <= 1'b0;

    if( perph_req_valid[Mem] && perph_req_ack[Mem] ) begin
        if( perph_req_write[Mem] ) begin
        end else begin
            perph_rsp_valid[Mem] <= 1'b1;
            perph_rsp_data[Mem] <= perph_req_addr[Mem][15:8] - perph_req_addr[Mem][7:0];
        end
    end
end

apple_io io(
    .clock_i(clock),

    .cpu_req_valid_i(cpu_req_valid),
    .cpu_req_addr_i(cpu_req_addr),
    .cpu_req_ack_o(cpu_req_ack),
    .cpu_req_write_i(cpu_req_write),
    .cpu_req_data_i(cpu_req_data),

    .cpu_rsp_valid_o(cpu_rsp_valid),
    .cpu_rsp_data_o(cpu_rsp_data),

    .perph_req_valid_o(perph_req_valid),
    .perph_req_ack_i(perph_req_ack),
    .perph_req_addr_o(perph_req_addr),
    .perph_req_write_o(perph_req_write),
    .perph_req_write_data_o(perph_req_data),

    .perph_rsp_valid_i(perph_rsp_valid),
    .perph_rsp_read_data_i(perph_rsp_data)
);

endmodule
