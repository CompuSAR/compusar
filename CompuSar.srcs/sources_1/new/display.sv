`timescale 1ns / 1ps

module display# (
    SOUTH_BUS_WIDTH = 128
)(
    input raw_clock_i,
    input ctrl_clock_i,
    input reset_i,
    input reset8_i,

    input ctrl_req_valid_i,
    output logic ctrl_req_ack_o = 1'b1,
    input [15:0] ctrl_req_addr_i,
    input ctrl_req_write_i,
    input [31:0] ctrl_req_data_i,
    output logic ctrl_rsp_valid_o,
    output [31:0] ctrl_rsp_data_o,

    output logic dma_req_valid_o,
    output [SOUTH_BUS_WIDTH/8-1:0] dma_req_write_mask_o,
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

assign dma_req_write_mask_o = { SOUTH_BUS_WIDTH/8{1'b0} };

/********************* CDC logic *******************/
wire vertical_blank_hdmi, vertical_blank_cpu;
wire pixel_clk;

xpm_cdc_single cdc_vblank(
    .src_in(vertical_blank_hdmi),
    .src_clk(pixel_clk),

    .dest_out(vertical_blank_cpu),
    .dest_clk(ctrl_clock_i)
);

localparam DISPLAY32_PIXEL_BITS = SOUTH_BUS_WIDTH/8 * 25;       // 25 bits per pixel
localparam CDC_PIXELS32_WIDTH =
    DISPLAY32_PIXEL_BITS
    + 10                        // X coordinate
    + 10;                       // Y coordinate

wire [CDC_PIXELS32_WIDTH-1:0] pixels32_cdc_ctrl, pixels32_cdc_hdmi;
wire pixels32_cdc_valid_ctrl, pixels32_cdc_valid_hdmi;
wire pixels32_cdc_ack_ctrl, pixels32_cdc_ack_hdmi;

xpm_cdc_handshake#(
    .WIDTH( CDC_PIXELS32_WIDTH )
) pixels32_cdc(
    .src_clk( ctrl_clock_i ),
    .src_in( pixels32_cdc_ctrl ),
    .src_send( pixels32_cdc_valid_ctrl ),
    .src_rcv( pixels32_cdc_ack_ctrl ),

    .dest_clk( pixel_clk ),
    .dest_out( pixels32_cdc_hdmi ),
    .dest_req( pixels32_cdc_valid_hdmi ),
    .dest_ack( pixels32_cdc_ack_hdmi )
);

/******************** CPU clock *********************/
assign ctrl_rsp_data_o = 32'h0;

logic [31:0] base_addr_reg, frame_height_width_reg, frame_start_reg;

always_ff@(posedge ctrl_clock_i) begin
    ctrl_rsp_valid_o <= 1'b0;

    if( ctrl_req_valid_i && ctrl_req_ack_o ) begin
        if( ctrl_req_write_i ) begin
            casex( ctrl_req_addr_i )
                16'h0000: base_addr_reg <= ctrl_req_data_i;
                16'h0004: frame_height_width_reg <= ctrl_req_data_i;
                16'h0008: frame_start_reg <= ctrl_req_data_i;
            endcase
        end else begin
            ctrl_rsp_valid_o <= 1'b1;
        end
    end
end

display_32bit display_32bit(
    .ctrl_clock_i,
    .reset_i,
    .vsync_i(vertical_blank_cpu),

    .frame_base_addr_i(base_addr_reg),
    .frame_height_i(frame_height_width_reg[25:16]),
    .frame_width_i(frame_height_width_reg[9:0]),
    .frame_start_x(frame_start_reg[9:0]),
    .frame_start_y(frame_start_reg[25:16]),

    .pixels(pixels32_cdc_ctrl[DISPLAY32_PIXEL_BITS-1:0]),
    .display_x(pixels32_cdc_ctrl[DISPLAY32_PIXEL_BITS+9:DISPLAY32_PIXEL_BITS]),
    .display_y(pixels32_cdc_ctrl[DISPLAY32_PIXEL_BITS+19:DISPLAY32_PIXEL_BITS+10]),
    .pixels_ready(pixels32_cdc_valid_ctrl),
    .pixels_ack(pixels32_cdc_ack_ctrl),

    .dma_req_valid_o,
    .dma_req_addr_o,
    .dma_req_ack_i,
    .dma_rsp_valid_i,
    .dma_rsp_data_i
);

/******************** PIXEL clock *******************/
wire [9:0] cx, cy, frame_width, frame_height, screen_width, screen_height;
wire [23:0] rgb;

display_aggregator#(
    .NUM_PIXELS32(SOUTH_BUS_WIDTH/8)
) aggregator(
    .clock_i( pixel_clk ),

    .cx( cx ),
    .cy( cy ),
    .screen_width( screen_width ),
    .screen_height( screen_height ),
    .frame_width( frame_width ),
    .frame_height( frame_height ),

    .vsync( vertical_blank_hdmi ),

    .pixels32_valid( pixels32_cdc_valid_hdmi ),
    .pixels32( pixels32_cdc_hdmi[DISPLAY32_PIXEL_BITS-1:0] ),
    .pixels32_x( pixels32_cdc_hdmi[DISPLAY32_PIXEL_BITS+9:DISPLAY32_PIXEL_BITS] ),
    .pixels32_y( pixels32_cdc_hdmi[DISPLAY32_PIXEL_BITS+19:DISPLAY32_PIXEL_BITS+10] ),
    .pixels32_ack( pixels32_cdc_ack_hdmi ),

    .rgb(rgb)
);

hdmi_wrapper hdmi(
    .raw_clock_i,
    .clk_pixel_o(pixel_clk),
    .clk_audio(1'b0),
    .reset(1'b0),
    .rgb( rgb ),
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
