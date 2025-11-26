`timescale 1ns / 1ps

module display_aggregator#(
    NUM_PIXELS32 = 16
)(
    input clock_i,

    input [9:0] cx,
    input [9:0] cy,
    input [9:0] screen_width,
    input [9:0] screen_height,
    input [9:0] frame_width,
    input [9:0] frame_height,

    output vsync,

    input pixels32_valid,
    input [NUM_PIXELS32 * 25 - 1:0] pixels32,
    input [9:0] pixels32_x,
    input [9:0] pixels32_y,
    output logic pixels32_ack = 1'b0,

    output [23:0] rgb
);

// TODO maybe use just the y criteria?
assign vsync = cy > screen_height || (cy == screen_height && cx >= screen_width);

// TODO TRANSPARENT_PIXEL is currently set to just black. Update it when
// introducing the 8 bit pixels
localparam TRANSPARENT_PIXEL = 24'h0ffff11;

logic [$clog2(NUM_PIXELS32+1)-1:0] buf32_fill = 0;
logic [NUM_PIXELS32 * 25 - 1:0] buf32;
logic [9:0] buf32_x, buf32_y;
wire buf32_valid, buf32_current;
assign buf32_valid = buf32_fill != 0;
assign buf32_current = buf32_valid && buf32_x==cx && buf32_y==cy;

wire [24:0] pixel32;
assign pixel32 = buf32_current ? buf32[24:0] : TRANSPARENT_PIXEL;

always_ff@(posedge clock_i) begin
    // Read the incoming buffer if it's and us are ready
    if( (!buf32_valid || buf32_fill==1) && pixels32_valid && !pixels32_ack ) begin
        buf32 <= pixels32;
        buf32_x <= pixels32_x;
        buf32_y <= pixels32_y;
        buf32_fill <= NUM_PIXELS32;
        pixels32_ack <= 1'b1;

        // Discard the buffer if we missed the right spot
        if( !vsync && (pixels32_y<cy || pixels32_y==cy && pixels32_x<cx) )
            buf32_fill <= 0;
    end

    if( pixels32_ack && !pixels32_valid )
        pixels32_ack <= 1'b0;

    // Our pixel is current
    if( buf32_current ) begin
        buf32_x <= buf32_x + 1;
        buf32_fill <= buf32_fill - 1;

        // Shift the buffer down
        buf32 <= { TRANSPARENT_PIXEL, buf32[NUM_PIXELS32 * 25 - 1:24] };
    end
end

assign rgb = pixel32[23:0];

endmodule
