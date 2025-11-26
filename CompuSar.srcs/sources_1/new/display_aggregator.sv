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

    output logic[23:0] rgb
);

// TODO maybe use just the y criteria?
assign vsync = cy > screen_height || (cy == screen_height && cx >= screen_width);

// TODO TRANSPARENT_PIXEL is currently set to just black. Update it when
// introducing the 8 bit pixels
localparam TRANSPARENT_PIXEL = 24'h0ffff11;

logic [$clog2(NUM_PIXELS32+1)-1:0] buf32_fill = 0;
logic [NUM_PIXELS32 * 25 - 1:0] buf32, fetch32;
logic [9:0] buf32_x, buf32_y, fetch32_x, fetch32_y;
logic fetch32_valid = 1'b0, buf32_valid = 1'b0;

wire [24:0] pixel32;
assign pixel32 = buf32_valid ? buf32[24:0] : TRANSPARENT_PIXEL;

always_ff@(posedge clock_i) begin
    // Read the incoming buffer if it's and us are ready
    if( !fetch32_valid && pixels32_valid && !pixels32_ack ) begin
        fetch32 <= pixels32;
        fetch32_x <= pixels32_x;
        fetch32_y <= pixels32_y;
        fetch32_valid <= 1'b1;
        pixels32_ack <= 1'b1;
    end

    if( pixels32_ack && !pixels32_valid )
        pixels32_ack <= 1'b0;
    
    // Discard stale buffers
    if( fetch32_valid && !vsync && (fetch32_y < cy || (fetch32_y == cy && fetch32_x < cx)) ) begin
        fetch32_valid <= 1'b0;
    end

    if( buf32_fill == 0 )
        buf32_valid <= 1'b0;

    if( buf32_fill == 0 && fetch32_valid && fetch32_y==cy && fetch32_x==cx+1 ) begin
        buf32 <= fetch32;
        buf32_fill <= NUM_PIXELS32 - 1;

        fetch32_valid <= 1'b0;
        buf32_valid <= 1'b1;
    end

    if( buf32_fill != 0 ) begin
        buf32_fill <= buf32_fill - 1;

        // Shift the buffer down
        buf32 <= { 25'hX, buf32[NUM_PIXELS32 * 25 - 1:25] };
    end
    
    rgb <= pixel32[23:0];
end

endmodule
