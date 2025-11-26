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
logic [9:0] display_x, display_y;
logic pixels_ready, pixels_ack = 1'b0;

logic dma_req_valid, dma_req_ack = 1'b1, dma_rsp_valid = 1'b0;
logic [31:0] dma_req_addr;
logic [127:0] dma_rsp_data;

always_ff@(posedge clock) begin
    dma_rsp_valid <= 1'b0;
    if( dma_req_valid && dma_req_ack ) begin
        dma_rsp_valid <= 1'b1;
        dma_rsp_data <= memory[dma_req_addr[9:0]];
    end
end

logic [200-1:0] ack_delay = 200'b0;

always_ff@(posedge clock) begin
    ack_delay <= { pixels_ready, ack_delay[199:1] };
    pixels_ack <= ack_delay[0];
end

display_32bit display(
    .ctrl_clock_i(clock),
    .reset_i(reset),
    .vsync_i(vsync),

    .frame_base_addr_i(32'h00000000),
    .frame_width_i(128),
    .frame_height_i(5),
    .frame_start_x(13),
    .frame_start_y(27),

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

initial begin
    forever begin
        #40000 vsync = 1'b1;
        #100 vsync = 1'b0;
    end
end

wire [24:0]pixels_indexed[16];

genvar i;
generate

for( i=0; i<16; ++i )
    assign pixels_indexed[i] = pixels[i*25+24:i*25];

endgenerate

endmodule
