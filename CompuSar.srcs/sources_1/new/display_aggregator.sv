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
    output pixels32_ack,

    output [23:0] rgb
);

assign vsync = cy > screen_height || (cy == screen_height && cx >= screen_width);

endmodule
