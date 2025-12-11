`timescale 1ns / 1ps

module display# (
    SOUTH_BUS_WIDTH = 128
)(
    input raw_clock_i,
    input ctrl_clock_i,
    input reset32_i,
    input reset8_i,
    output vsync_irq_o,

    input ctrl_req_valid_i,
    output ctrl_req_ack_o,
    input [15:0] ctrl_req_addr_i,
    input ctrl_req_write_i,
    input [31:0] ctrl_req_data_i,
    output logic ctrl_rsp_valid_o,
    output [31:0] ctrl_rsp_data_o,

    output logic dma32_req_valid_o,
    output [SOUTH_BUS_WIDTH/8-1:0] dma32_req_write_mask_o,
    output logic [31:0] dma32_req_addr_o,
    input dma32_req_ack_i,
    input dma32_rsp_valid_i,
    input [SOUTH_BUS_WIDTH-1:0] dma32_rsp_data_i,

    output logic dma8_req_valid_o,
    output [SOUTH_BUS_WIDTH/8-1:0] dma8_req_write_mask_o,
    output logic [31:0] dma8_req_addr_o,
    input dma8_req_ack_i,
    input dma8_rsp_valid_i,
    input [SOUTH_BUS_WIDTH-1:0] dma8_rsp_data_i,

    output wire TMDS_clk_n,
    output wire TMDS_clk_p,
    output wire[2:0] TMDS_data_n,
    output wire[2:0] TMDS_data_p,
    output wire[0:0] HDMI_OEN
);

assign HDMI_OEN = 1'b1;

assign dma32_req_write_mask_o = { SOUTH_BUS_WIDTH/8{1'b0} };
assign dma8_req_write_mask_o = { SOUTH_BUS_WIDTH/8{1'b0} };

/********************* CDC logic *******************/
wire vertical_blank_hdmi, vertical_blank_cpu;
wire vertical_sync_hdmi, vertical_sync_cpu;
wire pixel_clk;

xpm_cdc_single cdc_vblank(
    .src_in(vertical_blank_hdmi),
    .src_clk(pixel_clk),

    .dest_out(vertical_blank_cpu),
    .dest_clk(ctrl_clock_i)
);

xpm_cdc_single cdc_vsync(
    .src_in(vertical_sync_hdmi),
    .src_clk(pixel_clk),

    .dest_out(vertical_sync_cpu),
    .dest_clk(ctrl_clock_i)
);

localparam DISPLAY32_PIXEL_BITS = SOUTH_BUS_WIDTH/8 * 25;       // 25 bits per pixel
localparam CDC_PIXELS32_WIDTH =
    DISPLAY32_PIXEL_BITS
    + 10                        // X coordinate
    + 10;                       // Y coordinate

/******************** CPU clock *********************/
assign ctrl_rsp_data_o = 32'h0;

logic prev_vblank = 1'b0;
logic [31:0] base_addr_reg, frame_height_width_reg, frame_start_reg, irqs = 32'h0;
assign vsync_irq_o = irqs[0];

always_ff@(posedge ctrl_clock_i) begin
    ctrl_rsp_valid_o <= 1'b0;

    if( !prev_vblank && vertical_blank_cpu )
        irqs[0] <= 1'b1;
    prev_vblank <= vertical_blank_cpu;

    if( ctrl_req_valid_i && ctrl_req_ack_o ) begin
        if( ctrl_req_write_i ) begin
            case( ctrl_req_addr_i )
                16'h0000: base_addr_reg <= ctrl_req_data_i;
                16'h0004: frame_height_width_reg <= ctrl_req_data_i;
                16'h0008: frame_start_reg <= ctrl_req_data_i;
                16'h000c: irqs <= 32'h0;
            endcase
        end else begin
            ctrl_rsp_valid_o <= 1'b1;
        end
    end
end

logic pixel32_valid, pixel32_ack;
logic [9:0] pixel32_x, pixel32_y;
logic [24:0] pixel32_data;

display_32bit display_32bit(
    .ctrl_clock_i,
    .reset_i(reset32_i),
    .vblank_i(vertical_blank_cpu),
    .vsync_i(vertical_sync_cpu),

    .frame_base_addr_i(base_addr_reg),
    .frame_height_i(frame_height_width_reg[25:16]),
    .frame_width_i(frame_height_width_reg[9:0]),
    .frame_start_x(frame_start_reg[9:0]),
    .frame_start_y(frame_start_reg[25:16]),

    .dma_req_valid_o(dma32_req_valid_o),
    .dma_req_addr_o(dma32_req_addr_o),
    .dma_req_ack_i(dma32_req_ack_i),
    .dma_rsp_valid_i(dma32_rsp_valid_i),
    .dma_rsp_data_i(dma32_rsp_data_i),

    .pixel_clock_i(pixel_clk),

    .pixel_valid(pixel32_valid),
    .pixel(pixel32_data),
    .pixel_x(pixel32_x),
    .pixel_y(pixel32_y),
    .pixel_ack(pixel32_ack)
);

logic pixel8_valid, pixel8_ack;
logic [9:0] pixel8_x, pixel8_y;
logic [24:0] pixel8_data;

display_8bit display_8bit(
    .ctrl_clock_i,
    .reset_i(reset8_i),
    .vblank_i(vertical_blank_cpu),
    .vsync_i(vertical_sync_cpu),

    .ctrl_req_valid_i( ctrl_req_valid_i && ctrl_req_addr_i[15] ),
    .ctrl_req_addr_i,
    .ctrl_req_write_i,
    .ctrl_req_data_i,
    .ctrl_req_ack_o(ctrl_req_ack_o),    // Only the 8 bit controller may signal not ready

    .dma_req_valid_o(dma8_req_valid_o),
    .dma_req_addr_o(dma8_req_addr_o),
    .dma_req_ack_i(dma8_req_ack_i),
    .dma_rsp_valid_i(dma8_rsp_valid_i),
    .dma_rsp_data_i(dma8_rsp_data_i),

    .pixel_clock_i(pixel_clk),

    .pixel_valid(pixel8_valid),
    .pixel(pixel8_data),
    .pixel_x(pixel8_x),
    .pixel_y(pixel8_y),
    .pixel_ack(pixel8_ack)
);

/******************** PIXEL clock *******************/
wire [9:0] cx, cy, frame_width, frame_height, screen_width, screen_height;
wire [23:0] rgb;

display_aggregator aggregator(
    .clock_i( pixel_clk ),

    .cx( cx ),
    .cy( cy ),
    .screen_width( screen_width ),
    .screen_height( screen_height ),
    .frame_width( frame_width ),
    .frame_height( frame_height ),

    .vsync( vertical_sync_hdmi ),
    .vblank( vertical_blank_hdmi ),

    .pixel32_valid,
    .pixel32(pixel32_data),
    .pixel32_x,
    .pixel32_y,
    .pixel32_ack,

    .pixel8_valid,
    .pixel8(pixel8_data),
    .pixel8_x,
    .pixel8_y,
    .pixel8_ack,

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
