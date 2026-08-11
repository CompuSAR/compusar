`timescale 1ns / 1ps

module display_8bit# (
    SOUTH_BUS_WIDTH = 128
)(
    // Ctrl clock signals
    input ctrl_clock_i,
    input reset_i,
    input vblank_i,
    input vsync_i,

    input ctrl_req_valid_i,
    output logic ctrl_req_ack_o = 1'b1,
    input [15:0] ctrl_req_addr_i,
    input ctrl_req_write_i,
    input [31:0] ctrl_req_data_i,

    sync_bus_write_mask.MASTER dma,

    // Pixel clock signals
    input pixel_clock_i,

    output pixel_valid,
    output [24:0] pixel,
    output [9:0] pixel_x,
    output [9:0] pixel_y,
    input pixel_ack
);

assign dma.req_valid = 1'b0;
assign pixel_valid = 1'b0;

always_ff@(posedge ctrl_clock_i) begin
end

endmodule
