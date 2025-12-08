`timescale 1ns / 1ps

module display_32bit#(
    SOUTH_BUS_WIDTH = 128
)(
    input ctrl_clock_i,
    input reset_i,
    input vsync_i,

    input [31:0] frame_base_addr_i,
    input [9:0] frame_width_i,
    input [9:0] frame_height_i,

    input [9:0] frame_start_x,
    input [9:0] frame_start_y,

    output logic [SOUTH_BUS_WIDTH/8 * 25 - 1:0] pixels,
    output logic [9:0] display_x,
    output logic [9:0] display_y,
    output logic pixels_ready = 1'b0,
    input pixels_ack,

    output logic dma_req_valid_o = 1'b0,
    output logic [31:0] dma_req_addr_o,
    input dma_req_ack_i,
    input dma_rsp_valid_i,
    input [SOUTH_BUS_WIDTH-1:0] dma_rsp_data_i
);

localparam PIXELS_BURST = SOUTH_BUS_WIDTH/8;
localparam TRANSPARENT_PIXEL = { 1'b1, 8'h00, 8'b00100100, 8'h00 };
logic prev_vsync = 1'b0;

logic [24:0] work_pixels[PIXELS_BURST];
logic [25*PIXELS_BURST - 1:0] work_pixels_packed;
logic [31:0] fetch_addr;
logic [9:0] screen_pos_x, start_pos_x, screen_pos_y, start_pos_y, width, height;

logic [SOUTH_BUS_WIDTH-1:0] fetch_buffer, work_buffer;
logic fetch_buffer_valid = 1'b0, dma_fetch_in_progress = 1'b0, display_done = 1'b1;
logic work_buffer_valid = 1'b0, work_pixels_valid = 1'b0;

wire [7:0] work_buffer_indexed[PIXELS_BURST];

task reset_all();
    int i;

    dma_req_valid_o <= 1'b0;
    fetch_buffer_valid <= 1'b0;
    work_buffer_valid <= 1'b0;
    work_pixels_valid <= 1'b0;
    dma_fetch_in_progress <= 1'b0;
    display_done <= 1'b0;

    fetch_addr <= frame_base_addr_i;
    start_pos_x <= frame_start_x;
    start_pos_y <= frame_start_y;
    screen_pos_x <= 0;
    screen_pos_y <= 0;
    width <= frame_width_i;
    height <= frame_height_i;

    pixels_ready <= 1'b0;
    for( i=0; i<PIXELS_BURST; ++i )
        work_pixels[i] <= TRANSPARENT_PIXEL;
endtask

function [24:0] convert_pixel([7:0] data);
    // Transparency bit
    convert_pixel[24] = data[7];
    // Red
    convert_pixel[23:22] = data[6:5];
    convert_pixel[21:20] = data[6:5];
    convert_pixel[19:18] = data[6:5];
    convert_pixel[17:16] = data[6:5];
    // Green
    convert_pixel[15:13] = data[4:2];
    convert_pixel[12:10] = data[4:2];
    convert_pixel[9:8]   = data[4:3];
    // Blue
    convert_pixel[7:6] = data[1:0];
    convert_pixel[5:4] = data[1:0];
    convert_pixel[3:2] = data[1:0];
    convert_pixel[1:0] = data[1:0];
endfunction

task ctrl_cycle();
    int i;

    if( !display_done )  begin
        // Fetch if needed
        if( !fetch_buffer_valid && !dma_fetch_in_progress ) begin
            dma_req_valid_o <= 1'b1;
            dma_req_addr_o <= fetch_addr;
        end

        if( dma_req_valid_o && dma_req_ack_i ) begin
            dma_req_valid_o <= 1'b0;
            dma_fetch_in_progress <= 1'b1;
        end

        // Fetch results arrived
        if( dma_rsp_valid_i && dma_fetch_in_progress ) begin
            fetch_buffer <= dma_rsp_data_i;
            fetch_buffer_valid <= 1'b1;
            dma_fetch_in_progress <= 1'b0;

            fetch_addr <= fetch_addr + PIXELS_BURST;
        end

        // Fetch buffer has relevant data
        if( fetch_buffer_valid && !work_buffer_valid ) begin
            work_buffer <= fetch_buffer;
            work_buffer_valid <= 1'b1;
            fetch_buffer_valid <= 1'b0;
        end

        // Pixels to convert
        if( work_buffer_valid && !work_pixels_valid ) begin
            for( i=0; i<PIXELS_BURST; ++i )
                work_pixels[i] <= convert_pixel(work_buffer_indexed[i]);

            work_pixels_valid <= 1'b1;
            work_buffer_valid <= 1'b0;
        end

        // Send pixels to HDMI clock domain
        if( work_pixels_valid && !pixels_ready && !pixels_ack ) begin
            pixels <= work_pixels_packed;
            pixels_ready <= 1'b1;
            display_x <= start_pos_x + screen_pos_x;
            display_y <= start_pos_y + screen_pos_y;

            work_pixels_valid <= 1'b0;

            if( screen_pos_x < (width - PIXELS_BURST) ) begin
                screen_pos_x <= screen_pos_x + PIXELS_BURST;
            end else if( screen_pos_y == height-2 ) begin
                display_done <= 1'b1;
            end else begin
                screen_pos_x <= 0;
                screen_pos_y <= screen_pos_y + 1;
            end
        end
    end

    // Finish CDC handshake, even if that was the last batch
    if( pixels_ready && pixels_ack ) begin
        pixels_ready <= 1'b0;
    end
endtask

always_ff@(posedge ctrl_clock_i) begin
    prev_vsync <= vsync_i;

    if( reset_i || (vsync_i && !prev_vsync) )
        reset_all();
    else
        ctrl_cycle();
end

genvar i;

generate

for(i=0; i<PIXELS_BURST; ++i) begin
    assign work_buffer_indexed[i] = work_buffer[i*8+7:i*8];
    assign work_pixels_packed[25*i+24:25*i] = work_pixels[i];
end

endgenerate

endmodule
