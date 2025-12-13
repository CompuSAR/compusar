`timescale 1ns / 1ps

module display_32bit#(
    SOUTH_BUS_WIDTH = 128,
    COORDINATE_WIDTH = 10
)(
    // Ctrl clock signals
    input ctrl_clock_i,
    input reset_i,
    input vblank_i,
    input vsync_i,

    input [31:0] frame_base_addr_i,
    input [COORDINATE_WIDTH-1:0] frame_width_i,
    input [COORDINATE_WIDTH-1:0] frame_height_i,

    input [COORDINATE_WIDTH-1:0] frame_start_x,
    input [COORDINATE_WIDTH-1:0] frame_start_y,

    output logic dma_req_valid_o = 1'b0,
    output logic [31:0] dma_req_addr_o,
    input dma_req_ack_i,
    input dma_rsp_valid_i,
    input [SOUTH_BUS_WIDTH-1:0] dma_rsp_data_i,

    // Pixel clock signals
    input pixel_clock_i,

    output pixel_valid,
    output logic [24:0] pixel,
    output logic [COORDINATE_WIDTH-1:0] pixel_x,
    output logic [COORDINATE_WIDTH-1:0] pixel_y,
    input pixel_ack
);

localparam PIXELS_BURST = SOUTH_BUS_WIDTH/8;
localparam TRANSPARENT_PIXEL = { 1'b1, 8'h00, 8'b00100100, 8'h00 };

localparam PIPELINE_STAGES = 4;

localparam PIPELINE_DMA = 0;
localparam PIPELINE_CDC_CPU = 1;
localparam PIPELINE_HDMI = 2;
localparam PIPELINE_OUT = 3;

logic [SOUTH_BUS_WIDTH-1:0] frame_data[PIPELINE_STAGES];
logic [PIPELINE_STAGES-1:0] frame_data_valid = 0;
logic [COORDINATE_WIDTH-1:0] frame_x[PIPELINE_STAGES], frame_y[PIPELINE_STAGES];
logic dma_req_sent = 1'b0;
logic [COORDINATE_WIDTH-1:0] current_x, current_y, frame_width, frame_height;
logic [$clog2(PIXELS_BURST)-1:0] frame_out_fill;

logic [SOUTH_BUS_WIDTH-1:0] cdc_frame_data;
logic [COORDINATE_WIDTH-1:0] cdc_frame_x, cdc_frame_y;
logic cdc_send_cpu = 1'b0, cdc_send_hdmi, cdc_ack_cpu, cdc_ack_hdmi = 1'b0;

logic display_done = 1'b1;      // Start as idle until vsync

task do_reset();
    display_done <= 1'b1;
    frame_data_valid[PIPELINE_DMA] <= 1'b0;
    frame_data_valid[PIPELINE_CDC_CPU] <= 1'b0;
    dma_req_sent <= 1'b0;

    frame_width <= frame_width_i;
    frame_height <= frame_height_i;
    dma_req_addr_o <= frame_base_addr_i;
    frame_x[PIPELINE_DMA] <= frame_start_x;
    frame_y[PIPELINE_DMA] <= frame_start_y;
    current_x <= 0;
    current_y <= 0;
endtask

task do_cpu_cycle();
    if( cdc_send_cpu && cdc_ack_cpu ) begin
        // CDC acked
        cdc_send_cpu <= 1'b0;
        frame_data_valid[PIPELINE_CDC_CPU] <= 1'b0;
    end

    if( frame_data_valid[PIPELINE_CDC_CPU] && !cdc_ack_cpu ) begin
        // Send to CDC
        cdc_send_cpu <= 1'b1;
    end

    if( !frame_data_valid[PIPELINE_CDC_CPU] && frame_data_valid[PIPELINE_DMA] ) begin
        // Handle result of DMA
        frame_data_valid[PIPELINE_CDC_CPU] <= 1'b1;
        frame_data[PIPELINE_CDC_CPU] <= frame_data[PIPELINE_DMA];
        frame_x[PIPELINE_CDC_CPU] <= frame_x[PIPELINE_DMA] + current_x;
        frame_y[PIPELINE_CDC_CPU] <= frame_y[PIPELINE_DMA] + current_y;

        frame_data_valid[PIPELINE_DMA] <= 1'b0;
        dma_req_addr_o <= dma_req_addr_o + PIXELS_BURST;

        // Advance coordinates
        if( current_x < (frame_width - PIXELS_BURST) ) begin
            current_x <= current_x + PIXELS_BURST;
        end else if( current_y < frame_height - 1 ) begin
            current_x <= 0;
            current_y <= current_y + 1;
        end else begin
            display_done <= 1'b1;
        end
    end

    if( dma_rsp_valid_i && dma_req_sent ) begin
        // Response to DMA request
        frame_data[PIPELINE_DMA] <= dma_rsp_data_i;
        frame_data_valid[PIPELINE_DMA] <= 1'b1;

        dma_req_sent <= 1'b0;
    end

    if( dma_req_valid_o && dma_req_ack_i ) begin
        dma_req_valid_o <= 1'b0;
    end

    if( !frame_data_valid[PIPELINE_DMA] && !dma_req_sent && !display_done ) begin
        dma_req_valid_o <= 1'b1;
        dma_req_sent <= 1'b1;
    end
endtask

always_ff@(posedge ctrl_clock_i) begin
    if( reset_i ) begin
        do_reset();
    end else if( vblank_i ) begin
        if( !vsync_i )
            do_reset();
        else begin
            do_cpu_cycle();
            display_done <= 1'b0;
        end
    end else begin
        do_cpu_cycle();
    end
end

xpm_cdc_handshake#(
    .DEST_SYNC_FF(2),
    .SRC_SYNC_FF(2),
    .WIDTH(SOUTH_BUS_WIDTH + COORDINATE_WIDTH*2),
    .SIM_ASSERT_CHK(1)
) pixel_data_cdc(
    .src_clk(ctrl_clock_i),
    .src_in({frame_x[PIPELINE_CDC_CPU], frame_y[PIPELINE_CDC_CPU], frame_data[PIPELINE_CDC_CPU]}),
    .src_send(cdc_send_cpu),
    .src_rcv(cdc_ack_cpu),

    .dest_clk(pixel_clock_i),
    .dest_out({cdc_frame_x, cdc_frame_y, cdc_frame_data}),
    .dest_req(cdc_send_hdmi),
    .dest_ack(cdc_ack_hdmi)
);

assign pixel_valid = frame_data_valid[PIPELINE_OUT];
always_ff@(posedge pixel_clock_i) begin
    if( pixel_valid && pixel_ack ) begin
        // Successfully sent a pixel out

        // Shift all pixels
        frame_data[PIPELINE_OUT] <= { 8'hXX, frame_data[PIPELINE_OUT][SOUTH_BUS_WIDTH-1:8] };
        frame_out_fill <= frame_out_fill - 1;
        frame_x[PIPELINE_OUT] <= frame_x[PIPELINE_OUT] + 1;

        if( frame_out_fill==1 ) begin
            frame_data_valid[PIPELINE_OUT] <= 1'b0;
        end
    end

    if( frame_data_valid[PIPELINE_HDMI] && (!frame_data_valid[PIPELINE_OUT] || frame_out_fill==1) ) begin
        // Advance the CDC buffer to the output
        frame_data[PIPELINE_OUT] <= frame_data[PIPELINE_HDMI];
        frame_out_fill <= PIXELS_BURST;
        frame_x[PIPELINE_OUT] <= frame_x[PIPELINE_HDMI];
        frame_y[PIPELINE_OUT] <= frame_y[PIPELINE_HDMI];
        frame_data_valid[PIPELINE_OUT] <= 1'b1;
        frame_data_valid[PIPELINE_HDMI] <= 1'b0;
    end

    if( !frame_data_valid[PIPELINE_HDMI] && cdc_send_hdmi && !cdc_ack_hdmi ) begin
        cdc_ack_hdmi <= 1'b1;
        frame_data_valid[PIPELINE_HDMI] <= 1'b1;
        frame_data[PIPELINE_HDMI] <= cdc_frame_data;
        frame_x[PIPELINE_HDMI] <= cdc_frame_x;
        frame_y[PIPELINE_HDMI] <= cdc_frame_y;
    end

    if( !cdc_send_hdmi && cdc_ack_hdmi )
        cdc_ack_hdmi <= 1'b0;
end

always_comb begin
    pixel[24] = frame_data[PIPELINE_OUT][7];                                                                              // Transparency
    pixel[23:16] = {frame_data[PIPELINE_OUT][6:5], frame_data[PIPELINE_OUT][6:5], frame_data[PIPELINE_OUT][6:5], frame_data[PIPELINE_OUT][6:5]};        // Red
    pixel[15:8] = {frame_data[PIPELINE_OUT][4:2], frame_data[PIPELINE_OUT][4:2], frame_data[PIPELINE_OUT][4:3]};                              // Green
    pixel[7:0] = {frame_data[PIPELINE_OUT][1:0], frame_data[PIPELINE_OUT][1:0], frame_data[PIPELINE_OUT][1:0], frame_data[PIPELINE_OUT][1:0]};          // Blue

    pixel_x = frame_x[PIPELINE_OUT];
    pixel_y = frame_y[PIPELINE_OUT];
end

endmodule
