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

logic [SOUTH_BUS_WIDTH-1:0] frame_data_dma, frame_data_cdc_cpu, frame_data_cdc_hdmi, frame_data_out;
logic frame_data_dma_valid = 1'b0, frame_data_cdc_cpu_valid = 1'b0, frame_data_cdc_hdmi_valid = 1'b0, frame_data_out_valid = 1'b0;
logic dma_req_sent = 1'b0;
logic [COORDINATE_WIDTH-1:0]    display_x_base, display_y_base,
                                display_x_cpu, display_y_cpu,
                                display_x_hdmi, display_y_hdmi,
                                display_x_out, display_y_out;
logic [COORDINATE_WIDTH-1:0] current_x, current_y, frame_width, frame_height;
logic [$clog2(PIXELS_BURST)-1:0] frame_out_fill;

logic [SOUTH_BUS_WIDTH-1:0] cdc_frame_data;
logic [COORDINATE_WIDTH-1:0] cdc_frame_x, cdc_frame_y;
logic cdc_send_cpu = 1'b0, cdc_send_hdmi, cdc_ack_cpu, cdc_ack_hdmi = 1'b0;

logic display_done = 1'b1;      // Start as idle until vsync

task do_reset();
    display_done <= 1'b1;
    frame_data_dma_valid <= 1'b0;
    frame_data_cdc_cpu_valid <= 1'b0;
    dma_req_sent <= 1'b0;

    frame_width <= frame_width_i;
    frame_height <= frame_height_i;
    dma_req_addr_o <= frame_base_addr_i;
    display_x_base <= frame_start_x;
    display_y_base <= frame_start_y;
    current_x <= 0;
    current_y <= 0;

    // The following are not reset as they are on a different clock, and it's
    // not worth the trouble
    //frame_data_cdc_hdmi_valid <= 1'b0;
    //frame_data_out_valid <= 1'b0;
endtask

task do_cpu_cycle();
    if( cdc_send_cpu && cdc_ack_cpu ) begin
        // CDC acked
        cdc_send_cpu <= 1'b0;
        frame_data_cdc_cpu_valid <= 1'b0;
    end

    if( frame_data_cdc_cpu_valid && !cdc_ack_cpu ) begin
        // Send to CDC
        cdc_send_cpu <= 1'b1;
    end

    if( !frame_data_cdc_cpu_valid && frame_data_dma_valid ) begin
        // Handle result of DMA
        frame_data_cdc_cpu_valid <= 1'b1;
        frame_data_cdc_cpu <= frame_data_dma;
        display_x_cpu <= display_x_base + current_x;
        display_y_cpu <= display_y_base + current_y;

        frame_data_dma_valid <= 1'b0;
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
        frame_data_dma <= dma_rsp_data_i;
        frame_data_dma_valid <= 1'b1;

        dma_req_sent <= 1'b0;
    end

    if( dma_req_valid_o && dma_req_ack_i ) begin
        dma_req_valid_o <= 1'b0;
    end

    if( !frame_data_dma_valid && !dma_req_sent && !display_done ) begin
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
    .src_in({display_x_cpu, display_y_cpu, frame_data_cdc_cpu}),
    .src_send(cdc_send_cpu),
    .src_rcv(cdc_ack_cpu),

    .dest_clk(pixel_clock_i),
    .dest_out({cdc_frame_x, cdc_frame_y, cdc_frame_data}),
    .dest_req(cdc_send_hdmi),
    .dest_ack(cdc_ack_hdmi)
);

assign pixel_valid = frame_data_out_valid;
always_ff@(posedge pixel_clock_i) begin
    if( pixel_valid && pixel_ack ) begin
        // Successfully sent a pixel out

        // Shift all pixels
        frame_data_out <= { 8'hXX, frame_data_out[SOUTH_BUS_WIDTH-1:8] };
        frame_out_fill <= frame_out_fill - 1;
        display_x_out <= display_x_out + 1;

        if( frame_out_fill==1 ) begin
            frame_data_out_valid <= 1'b0;
        end
    end

    if( frame_data_cdc_hdmi_valid && (!frame_data_out_valid || frame_out_fill==1) ) begin
        // Advance the CDC buffer to the output
        frame_data_out <= frame_data_cdc_hdmi;
        frame_out_fill <= PIXELS_BURST;
        display_x_out <= display_x_hdmi;
        display_y_out <= display_y_hdmi;
        frame_data_out_valid <= 1'b1;
        frame_data_cdc_hdmi_valid <= 1'b0;
    end

    if( !frame_data_cdc_hdmi_valid && cdc_send_hdmi && !cdc_ack_hdmi ) begin
        cdc_ack_hdmi <= 1'b1;
        frame_data_cdc_hdmi_valid <= 1'b1;
        frame_data_cdc_hdmi <= cdc_frame_data;
        display_x_hdmi <= cdc_frame_x;
        display_y_hdmi <= cdc_frame_y;
    end

    if( !cdc_send_hdmi && cdc_ack_hdmi )
        cdc_ack_hdmi <= 1'b0;
end

always_comb begin
    pixel[24] = frame_data_out[7];                                                                              // Transparency
    pixel[23:16] = {frame_data_out[6:5], frame_data_out[6:5], frame_data_out[6:5], frame_data_out[6:5]};        // Red
    pixel[15:8] = {frame_data_out[4:2], frame_data_out[4:2], frame_data_out[4:3]};                              // Green
    pixel[7:0] = {frame_data_out[1:0], frame_data_out[1:0], frame_data_out[1:0], frame_data_out[1:0]};          // Blue

    pixel_x = display_x_out;
    pixel_y = display_y_out;
end

endmodule
