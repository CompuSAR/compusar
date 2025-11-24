`timescale 1ns / 1ps

module display# (
    SOUTH_BUS_WIDTH = 128
)(
    input raw_clock_i,
    input ctrl_clock_i,
    input reset_i,
    input reset8_i,

    input ctrl_req_valid_i,
    output ctrl_req_ack_o,
    input [15:0] ctrl_req_addr_i,
    input ctrl_req_write_i,
    input [31:0] ctrl_req_data_i,
    output ctrl_rsp_valid_o,
    output [31:0] ctrl_rsp_data_o,

    output logic dma_req_valid_o,
    output logic [31:0] dma_req_addr_o,
    input dma_req_ack_i,
    input dma_rsp_valid_i,
    input [SOUTH_BUS_WIDTH-1:0] dma_rsp_data_i,

    output wire TMDS_clk_n,
    output wire TMDS_clk_p,
    output wire[2:0] TMDS_data_n,
    output wire[2:0] TMDS_data_p,
    output wire[0:0] HDMI_OEN
);

/******************** CPU clock *********************/
display_32bit display_32bit(
    .ctrl_clock_i,
    .reset_i,
    .vsync_i(vertical_blank_cpu),

    .dma_req_valid_o,
    .dma_req_addr_o,
    .dma_req_ack_i,
    .dma_rsp_valid_i,
    .dma_rsp_data_i
);

/******************** PIXEL clock *******************/
wire pixel_clk;

wire [9:0] cx, cy, frame_width, frame_height, screen_width, screen_height;
wire vertical_blank_hdmi, vertical_blank_cpu;

assign vertical_blank_hdmi = cy > screen_height || (cy == screen_height && cx >= screen_width);

xpm_cdc_single(
    .src_in(vertical_blank_hdmi),
    .src_clk(pixel_clk),

    .dest_out(vertical_blank_cpu),
    .dest_clk(ctrl_clock_i)
);

hdmi_wrapper hdmi(
    .raw_clock_i,
    .clk_pixel_o(pixel_clk),
    .clk_audio(1'b0),
    .reset(1'b0),
    .rgb( 24'hffff11 ),
    .audio_sample_l( 16'h0000 ),
    .audio_sample_r( 16'h0000 ),

    // These outputs go to your HDMI port
    .TMDS_clk_n,
    .TMDS_clk_p,
    .TMDS_data_n,
    .TMDS_data_p,

    // All outputs below this line stay inside the FPGA
    // They are used (by you) to pick the color each pixel should have
    // i.e. always_ff @(posedge pixel_clk) rgb <= {8'd0, 8'(cx), 8'(cy)};
    .cx(cx),
    .cy(cy),

    // The screen is at the upper left corner of the frame.
    // 0,0 = 0,0 in video
    // the frame includes extra space for sending auxiliary data
    .frame_width(frame_width),
    .frame_height(frame_height),
    .screen_width(screen_width),
    .screen_height(screen_height)
);

endmodule
