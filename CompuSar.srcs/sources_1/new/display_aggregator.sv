`timescale 1ns / 1ps

module display_aggregator(
    input clock_i,

    input [9:0] cx,
    input [9:0] cy,
    input [9:0] screen_width,
    input [9:0] screen_height,
    input [9:0] frame_width,
    input [9:0] frame_height,

    output vblank,
    output vsync,

    input pixel32_valid,
    input [24:0] pixel32,
    input [9:0] pixel32_x,
    input [9:0] pixel32_y,
    output pixel32_ack,

    input pixel8_valid,
    input [23:0] pixel8,
    input [9:0] pixel8_x,
    input [9:0] pixel8_y,
    output pixel8_ack,

    output logic[23:0] rgb
);

localparam VSYNC_LINES = 2;

// TODO maybe use just the y criteria?
assign vblank = cy > screen_height || (cy == screen_height && cx >= screen_width);
assign vsync = cy >= frame_height - VSYNC_LINES;

// A pixel color we special-case for fully transparent
localparam TRANSPARENT_PIXEL = 25'h1002400;
//localparam BACKGROUND_COLOR = 24'h000000;
localparam BACKGROUND_COLOR = 24'h000000;

logic [24:0] active_pixel32;
logic [23:0] active_pixel8;
logic [9:0] combined_red, combined_green, combined_blue;

always_comb begin
    combined_red = { active_pixel32[23:16], 2'b00 } + { 1'b0, active_pixel32[23:16], 1'b0 } + { 2'b00, active_pixel8[23:16] };
    combined_green = { active_pixel32[15:8], 2'b00 } + { 1'b0, active_pixel32[15:8], 1'b0 } + { 2'b00, active_pixel8[15:8] };
    combined_blue = { active_pixel32[7:0], 2'b00 } + { 1'b0, active_pixel32[7:0], 1'b0 } + { 2'b00, active_pixel8[7:0] };

    if( !active_pixel32[24] ) begin
        rgb = active_pixel32[23:0];
    end else if( active_pixel32 == TRANSPARENT_PIXEL ) begin
        rgb = active_pixel8;
    end else begin
        rgb = { combined_red[9:2], combined_green[9:2], combined_blue[9:2] };
    end
end

logic [24:0] buffered_pixel32;
logic [23:0] buffered_pixel8;
logic buffered_pixel32_valid = 1'b0, buffered_pixel8_valid = 1'b0;
logic [9:0] buffered32_x, buffered32_y, buffered8_x, buffered8_y;

// Indicates whether the pixel is consumed by the current cycle
logic shift32, shift8;

always_comb begin
    shift32 = 1'b0;
    active_pixel32 = TRANSPARENT_PIXEL;

    if( buffered_pixel32_valid ) begin
        if( buffered32_x == cx && buffered32_y == cy ) begin
            shift32 = 1'b1;
            active_pixel32 = buffered_pixel32;
        end else if( !vblank && (buffered32_y<cy || (buffered32_y==cy && buffered32_x<cx)) ) begin
            shift32 = 1'b1;
            active_pixel32 = TRANSPARENT_PIXEL;
        end
    end
end

always_comb begin
    shift8 = 1'b0;
    active_pixel8 = BACKGROUND_COLOR;

    if( buffered_pixel8_valid ) begin
        if( buffered8_x == cx && buffered8_y == cy ) begin
            shift8 = 1'b1;
            active_pixel8 = buffered_pixel8;
        end else if( !vblank && (buffered8_y<cy || (buffered8_y==cy && buffered8_x<cx)) ) begin
            shift8 = 1'b1;
            active_pixel8 =BACKGROUND_COLOR;
        end
    end
end

assign pixel32_ack = shift32 || !buffered_pixel32_valid;
assign pixel8_ack = shift8 || !buffered_pixel8_valid;

always_ff@(posedge clock_i) begin
    if( shift32 )
        buffered_pixel32_valid <= 1'b0;

    if( shift8 )
        buffered_pixel8_valid <= 1'b0;

    // Buffer new value logic must be after clearing the old value, as both
    // can happen in the same cycle
    if( pixel32_valid && pixel32_ack ) begin
        buffered_pixel32_valid <= 1'b1;
        buffered_pixel32 <= pixel32;
        buffered32_x <= pixel32_x;
        buffered32_y <= pixel32_y;
    end

    if( pixel8_valid && pixel8_ack ) begin
        buffered_pixel8_valid <= 1'b1;
        buffered_pixel8 <= pixel8;
        buffered8_x <= pixel8_x;
        buffered8_y <= pixel8_y;
    end
end

endmodule
