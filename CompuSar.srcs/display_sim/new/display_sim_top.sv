`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/12/2025 04:27:01 PM
// Design Name: 
// Module Name: display_sim_top
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


module display_sim_top(
    );

logic cpu_clock = 1'b0, board_clock = 1'b0;
logic reset8 = 1'b1, reset32 = 1'b1;
logic [127:0] memory[1024];

initial forever begin
    // ~75 MHz
    #6.598 cpu_clock = 1'b1;
    #6.598 cpu_clock = 1'b0;
end

initial forever begin
    // 50 MHz
    #10 board_clock = 1'b1;
    #10 board_clock = 1'b0;
end

initial begin
    $readmemh("memory.mem", memory);
end

logic tmds_clk[2];
logic [2:0]tmds_data[2];

logic dma32_req_valid, dma32_req_ack = 1'b1, dma32_rsp_valid = 1'b0;
logic [3:0] dma32_req_write;
logic [31:0] dma32_req_addr;
logic [127:0] dma32_rsp_data;

logic dma8_req_valid, dma8_req_ack = 1'b1, dma8_rsp_valid = 1'b0;
logic [3:0] dma8_req_write;
logic [31:0] dma8_req_addr;
logic [127:0] dma8_rsp_data;

logic ctrl_req_valid = 1'b0, ctrl_req_ack, ctrl_req_write = 1'b0, ctrl_rsp_valid;
logic [15:0] ctrl_req_addr;
logic [31:0] ctrl_req_data, ctrl_rsp_data;

display display(
    .raw_clock_i(board_clock),
    .ctrl_clock_i(cpu_clock),
    .reset32_i(reset32),
    .reset8_i(reset8),

    .ctrl_req_valid_i(ctrl_req_valid),
    .ctrl_req_ack_o(ctrl_req_ack),
    .ctrl_req_addr_i(ctrl_req_addr),
    .ctrl_req_write_i(ctrl_req_write),
    .ctrl_req_data_i(ctrl_req_data),
    .ctrl_rsp_valid_o(ctrl_rsp_valid),
    .ctrl_rsp_data_o(ctrl_rsp_data),

    .dma32_req_valid_o(dma32_req_valid),
    .dma32_req_write_mask_o(dma32_req_write),
    .dma32_req_addr_o(dma32_req_addr),
    .dma32_req_ack_i(dma32_req_ack),
    .dma32_rsp_valid_i(dma32_rsp_valid),
    .dma32_rsp_data_i(dma32_rsp_data),

    .dma8_req_valid_o(dma8_req_valid),
    .dma8_req_write_mask_o(dma8_req_write),
    .dma8_req_addr_o(dma8_req_addr),
    .dma8_req_ack_i(dma8_req_ack),
    .dma8_rsp_valid_i(dma8_rsp_valid),
    .dma8_rsp_data_i(dma8_rsp_data),

    .TMDS_clk_n(tmds_clk[0]),
    .TMDS_clk_p(tmds_clk[1]),
    .TMDS_data_n(tmds_data[0]),
    .TMDS_data_p(tmds_data[1]),
    .HDMI_OEN()
);

initial begin
    reset32 = 1'b1;
    reset8 = 1'b1;

    ctrl_req_valid = 1'b0;

    // Initialize the display
    @(posedge cpu_clock);
    @(posedge cpu_clock);

    ctrl_req_valid = 1'b1;
    ctrl_req_addr = 16'h0000;           // Base fetch addr
    ctrl_req_data = 32'h00000400;
    ctrl_req_write = 1'b1;
    do
        @(posedge cpu_clock);
    while( !ctrl_req_ack );

    ctrl_req_addr = 16'h0004;           // height and width
    ctrl_req_data = (4<<16) | 32;
    do
        @(posedge cpu_clock);
    while( !ctrl_req_ack );

    ctrl_req_addr = 16'h0008;           // y and x display location
    ctrl_req_data = 8<<16 | 5;
    do
        @(posedge cpu_clock);
    while( !ctrl_req_ack );

    ctrl_req_valid = 1'b0;

    repeat(7) @(posedge cpu_clock);

    reset32 = 1'b0;
end

always_ff@(posedge cpu_clock) begin
    dma32_rsp_valid = 1'b0;

    if( dma32_req_valid && dma32_req_ack ) begin
        if( dma32_req_write == 0 ) begin
            dma32_rsp_valid = 1'b1;
            dma32_rsp_data = memory[dma32_req_addr[31:4]];
        end
    end
end

endmodule
