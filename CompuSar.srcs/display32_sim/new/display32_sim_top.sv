`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/24/2025 06:25:22 AM
// Design Name: 
// Module Name: display32_sim_top
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


module display32_sim_top(

    );

localparam FRAME_W = 800;
localparam FRAME_H = 525;
localparam SCREEN_W = 640;
localparam SCREEN_H = 480;

logic clock=1'b0;
logic reset=1'b1;
logic [127:0] memory[1024];

initial
    forever begin
        // 75MHz clock
        #6.667 clock = 1'b0;
        #6.666 clock = 1'b1;
    end

initial begin
    $readmemh("memory.mem", memory);
    #50 reset = 1'b0;
end

logic vsync = 1'b0;
logic [16*25-1:0] pixels;
logic [9:0] display_x, display_y, cx = 0, cy = 0;
logic pixels_ready, pixels_ack;

logic dma_req_valid, dma_req_ack = 1'b1, dma_rsp_valid = 1'b0;
logic [31:0] dma_req_addr;
logic [127:0] dma_rsp_data;

logic [23:0] rgb;

always_ff@(posedge clock) begin
    dma_rsp_valid <= 1'b0;
    if( dma_req_valid && dma_req_ack ) begin
        dma_rsp_valid <= 1'b1;
        dma_rsp_data <= memory[dma_req_addr[9:0]];
    end
end

display_32bit display(
    .ctrl_clock_i(clock),
    .reset_i(reset),
    .vsync_i(vsync),

    .frame_base_addr_i(32'h00000000),
    .frame_width_i(48),
    .frame_height_i(5),
    .frame_start_x(0),
    .frame_start_y(70),

    .pixels(pixels),
    .display_x(display_x),
    .display_y(display_y),
    .pixels_ready(pixels_ready),
    .pixels_ack(pixels_ack),

    .dma_req_valid_o(dma_req_valid),
    .dma_req_addr_o(dma_req_addr),
    .dma_req_ack_i(dma_req_ack),
    .dma_rsp_valid_i(dma_rsp_valid),
    .dma_rsp_data_i(dma_rsp_data)
);

display_aggregator#() aggregator(
    .clock_i(clock),

    .cx(cx),
    .cy(cy),
    .screen_width(SCREEN_W),
    .screen_height(SCREEN_H),
    .frame_width(FRAME_W),
    .frame_height(FRAME_H),

    .vsync(vsync),

    .pixels32_valid(pixels_ready),
    .pixels32(pixels),
    .pixels32_ack(pixels_ack),
    .pixels32_x(display_x),
    .pixels32_y(display_y),

    .rgb(rgb)
);

always_ff@(posedge clock) begin
    cx <= cx + 1;
    if( cx==FRAME_W-1 ) begin
        cx <= 0;
        cy <= cy + 1;

        if( cy==FRAME_H-1 )
            cy <= 0;
    end
end

wire [24:0]pixels_indexed[16];

genvar i;
generate

for( i=0; i<16; ++i )
    assign pixels_indexed[i] = pixels[i*25+24:i*25];

endgenerate

endmodule
