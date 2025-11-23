`timescale 1ns / 1ps

module hdmi_wrapper(
    input raw_clock_i,
    output clk_pixel_o,
    input clk_audio,
    // synchronous reset back to 0,0
    input reset,
    input [23:0] rgb,
    input [15:0] audio_sample_l, audio_sample_r,

    // These outputs go to your HDMI port
    output wire TMDS_clk_n,
    output wire TMDS_clk_p,
    output wire[2:0] TMDS_data_n,
    output wire[2:0] TMDS_data_p,
    
    // All outputs below this line stay inside the FPGA
    // They are used (by you) to pick the color each pixel should have
    // i.e. always_ff @(posedge pixel_clk) rgb <= {8'd0, 8'(cx), 8'(cy)};
    output [9:0] cx,
    output [9:0] cy,

    // The screen is at the upper left corner of the frame.
    // 0,0 = 0,0 in video
    // the frame includes extra space for sending auxiliary data
    output [9:0] frame_width,
    output [9:0] frame_height,
    output [9:0] screen_width,
    output [9:0] screen_height
);

wire clk_pixel_x5;
wire pll_locked, clk_feedback;

wire tmds_clock;
wire [2:0] tmds_data;

wire [15:0] audio_samples[1:0];

assign audio_samples[0] = audio_sample_l;
assign audio_samples[1] = audio_sample_r;

MMCME2_BASE#(
    .DIVCLK_DIVIDE(5),
    .CLKFBOUT_MULT_F(63.000),
    .CLKIN1_PERIOD(20.000),
    .CLKOUT0_DIVIDE_F(25.000),
    .CLKOUT1_DIVIDE(5)
) clocks(
    .CLKFBIN(clk_feedback),
    .CLKIN1(raw_clock_i),
    .RST(1'b0),
    .PWRDWN(1'b0),

    .LOCKED(pll_locked),
    .CLKFBOUT(clk_feedback),

    .CLKOUT0(clk_pixel_o),
    .CLKOUT1(clk_pixel_x5)
);

hdmi#(
    .VIDEO_REFRESH_RATE(60),
    .VENDOR_NAME("CompuSAR"),
    .PRODUCT_DESCRIPTION({"Apple ][", 64'b0}),
    .SOURCE_DEVICE_INFORMATION(8'h08)
) (
    .clk_pixel_x5(clk_pixel_x5),
    .clk_pixel(clk_pixel_o),
    .clk_audio(clk_audio),
    .reset(reset || !pll_locked),
    .rgb(rgb),
    .audio_sample_word(audio_samples),

    .tmds(tmds_data),
    .tmds_clock(tmds_clock),

    .cx(cx),
    .cy(cy),

    .frame_width(frame_width),
    .frame_height(frame_height),
    .screen_width(screen_width),
    .screen_height(screen_height)
);

genvar i;

generate
for( i=0; i<=2; ++i ) begin
    OBUFDS buffer( .I(tmds_data[i]), .O(TMDS_data_p[i]), .OB(TMDS_data_n[i]));
end

endgenerate

OBUFDS ( .I(tmds_clock), .O(TMDS_clk_p), .OB(TMDS_clk_n) );

endmodule
