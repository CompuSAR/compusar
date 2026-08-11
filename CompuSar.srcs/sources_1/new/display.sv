`timescale 1ns / 1ps

module display(
    input raw_clock_i,
    input ctrl_clock_i,
    input reset32_i,
    input reset8_i,
    output vsync_irq_o,

    sync_bus.SLAVE ctrl,

    sync_bus_write_mask.MASTER dma32,
    sync_bus_write_mask.MASTER dma8,

    output wire TMDS_clk_n,
    output wire TMDS_clk_p,
    output wire[2:0] TMDS_data_n,
    output wire[2:0] TMDS_data_p,
    output wire[0:0] HDMI_OEN
);

localparam SOUTH_BUS_WIDTH = $bits(dma32.req_data);

assign HDMI_OEN = 1'b1;

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
assign ctrl.rsp_data = 32'h0;

logic prev_vblank = 1'b0;
logic [31:0] base_addr_reg, frame_height_width_reg, frame_start_reg, irqs = 32'h0;
assign vsync_irq_o = irqs[0];

always_ff@(posedge ctrl_clock_i) begin
    ctrl.rsp_valid <= 1'b0;

    if( !prev_vblank && vertical_blank_cpu )
        irqs[0] <= 1'b1;
    prev_vblank <= vertical_blank_cpu;

    if( ctrl.req_valid && ctrl.req_ack ) begin
        if( ctrl.req_write ) begin
            case( ctrl.req_addr )
                16'h0000: base_addr_reg <= ctrl.req_data;
                16'h0004: frame_height_width_reg <= ctrl.req_data;
                16'h0008: frame_start_reg <= ctrl.req_data;
                16'h000c: irqs <= 32'h0;
            endcase
        end else begin
            ctrl.rsp_valid <= 1'b1;
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

    .dma(dma32),

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

    .ctrl_req_valid_i( ctrl.req_valid && ctrl.req_addr[15] ),
    .ctrl_req_addr_i( ctrl.req_addr ),
    .ctrl_req_write_i( ctrl.req_write ),
    .ctrl_req_data_i( ctrl.req_data ),
    .ctrl_req_ack_o( ctrl.req_ack ),    // Only the 8 bit controller may signal not ready

    .dma(dma8),

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
