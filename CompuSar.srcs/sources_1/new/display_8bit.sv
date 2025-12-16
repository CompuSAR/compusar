`timescale 1ns / 1ps

module display_8bit# (
    SOUTH_BUS_WIDTH = 128,
    COORDINATE_WIDTH = 10
)(
    // Ctrl clock signals
    input ctrl_clock_i,
    input reset_i,
    input vblank_i,
    input vsync_i,

    input ctrl_req_valid_i,
    output ctrl_req_ack_o,
    input [15:0] ctrl_req_addr_i,
    input ctrl_req_write_i,
    input [31:0] ctrl_req_data_i,

    output logic dma_req_valid_o = 1'b0,
    output logic [31:0] dma_req_addr_o,
    input dma_req_ack_i,
    input dma_rsp_valid_i,
    input [SOUTH_BUS_WIDTH-1:0] dma_rsp_data_i,

    // Pixel clock signals
    input pixel_clock_i,

    output logic pixel_valid,
    output logic [23:0] pixel,
    output logic [9:0] pixel_x,
    output logic [9:0] pixel_y,
    input pixel_ack
);

localparam PIXEL_ON_COLOR = 24'hffffff;
localparam PIXEL_OFF_COLOR = 24'h111111;

// Registers

logic [COORDINATE_WIDTH-1:0] base_display_x, base_display_y;
logic [31:0] base_addr_1, base_addr_split_1, base_addr_2, base_addr_split_2;
logic [31:0] display_mode;

localparam MODE__TEXT = 0;
localparam MODE__HIRES = 1;
localparam MODE__DOUBLE_RES = 2;

logic [31:0] charrom_write_data;
logic [11:0] charrom_write_addr;
logic charrom_write_enable = 1'b0;

logic [11:0] charrom_read_addr;
logic [7:0] charrom_read_data;
logic charrom_read_enable;

always_comb begin
    charrom_read_enable = frame_char_lookup_fill!=0;
charrom_read_addr = {2'b0, frame_data[PIPELINE_CHAR_LOOKUP][6:0], frame_char_lookup_line};
end

character_rom character_rom(
    .clka(ctrl_clock_i),
    .addra(charrom_write_addr),
    .dina(charrom_write_data),
    .ena(charrom_write_enable),
    .wea(1'b1),

    .clkb(ctrl_clock_i),
    .addrb(charrom_read_addr),
    .doutb(charrom_read_data),
    .enb(charrom_read_enable)
);

// Only allow new requests if the ctrl CDC is idle
assign ctrl_req_ack_o = 1'b1;

always_ff@(posedge ctrl_clock_i) begin
    charrom_write_enable <= 1'b0;

    if( ctrl_req_valid_i && ctrl_req_ack_o && ctrl_req_write_i ) begin
        casex( ctrl_req_addr_i )
            16'h8000: base_addr_1 <= ctrl_req_data_i;
            16'h8004: base_addr_split_1 <= ctrl_req_data_i;
            16'h8008: base_addr_2 <= ctrl_req_data_i;
            16'h800c: base_addr_split_2 <= ctrl_req_data_i;
            16'h8010: begin
                base_display_y <= ctrl_req_data_i[31:16];
                base_display_x <= ctrl_req_data_i[15:0];
            end
            16'h8014: display_mode <= ctrl_req_data_i;
            16'hfxxx: begin
                charrom_write_data <= ctrl_req_data_i;
                charrom_write_addr <= ctrl_req_addr_i[11:2];
                charrom_write_enable <= 1'b1;
            end
        endcase
    end
end

logic [REQ_BUS_BITS-1:0] dma_narrow_rsp_data;

bus_width_adjust#(.IN_WIDTH(REQ_BUS_BITS), .OUT_WIDTH(SOUTH_BUS_WIDTH), .ADDR_WIDTH(32)) dma_width_adjust(
    .clock_i(ctrl_clock_i),

    .in_cmd_valid_i(dma_req_valid_o),
    .in_cmd_addr_i(dma_req_addr_o),
    .in_cmd_write_mask_i(0),
    .in_cmd_write_data_i(),
    .in_rsp_read_data_o(dma_narrow_rsp_data),

    .out_cmd_ready_i(dma_req_ack_i),
    .out_cmd_write_mask_o(),
    .out_cmd_write_data_o(),
    .out_rsp_valid_i(dma_rsp_valid_i),
    .out_rsp_read_data_i(dma_rsp_data_i)
);

localparam PIPELINE_STAGES = 5;

localparam PIPELINE_DMA = 0;
localparam PIPELINE_CHAR_LOOKUP = 1;
localparam PIPELINE_HDMI = 2;
localparam PIPELINE_CDC_CPU = 3;
localparam PIPELINE_CDC_HDMI = 4;

localparam REQ_BUS_BYTES = 8;
localparam REQ_BUS_BITS = REQ_BUS_BYTES*8;
// Each byte in regular mode corresponds to 7 hi-res pixels, or 14 actual
// pixels. In doubel mode it corresponds to 7 actual pixels, but each fetch is
// actually two fetches.
localparam PIXELS_PER_BYTE = 7;
localparam FETCH_PIXELS = REQ_BUS_BYTES*PIXELS_PER_BYTE*2;

// Skip every other line
localparam Y_SPACING = 2;

logic [REQ_BUS_BITS-1:0] frame_data[PIPELINE_STAGES], pixel_cdc_data;
logic [PIPELINE_STAGES-1:0] frame_data_valid = 0;
logic [COORDINATE_WIDTH-1:0] frame_x[PIPELINE_STAGES], frame_y[PIPELINE_STAGES], pixel_cdc_x, pixel_cdc_y;
logic [7:0] frame_mode[PIPELINE_STAGES], pixel_cdc_mode;
logic [$clog2(REQ_BUS_BYTES+1)-1:0] frame_char_lookup_fill = 0;
logic [2:0] frame_char_lookup_line;
logic dma_req_sent = 1'b0;
logic [COORDINATE_WIDTH-1:0] current_x, current_y;

localparam SCREEN_LINE_BYTES = 40;
localparam SCREEN_LINES = 24 * 8;
logic [$clog2(3*SCREEN_LINE_BYTES+1)-1:0] screen_third_bias;    // Byte offset a result of the third of the screen we're in
logic [$clog2(SCREEN_LINE_BYTES)-1:0] screen_pos_horiz;
logic [$clog2(SCREEN_LINES)-1:0] screen_pos_vert = SCREEN_LINES;

wire [2:0] screen_pos_line_in_char;
assign screen_pos_line_in_char = screen_pos_vert[2:0];
wire [2:0] screen_pos_char_line_in_third;
assign screen_pos_char_line_in_third = screen_pos_vert[5:3];
wire [1:0] screen_pos_third;
assign screen_pos_third = screen_pos_vert[7:6];

wire display_done;
assign display_done = screen_pos_vert == SCREEN_LINES;

logic [31:0] dma_addr_offset;

wire bottom_4lines;
assign bottom_4lines = (screen_pos_third==2 && screen_pos_char_line_in_third[2]);
logic [7:0] active_mode;
logic [31:0] base_fetch_addr1, base_fetch_addr2;

always_comb begin
    if( bottom_4lines ) begin
        // Last 4 lines of the display may have a different setting
        active_mode = display_mode[7:0];
        base_fetch_addr1 = base_addr_split_1;
        base_fetch_addr2 = base_addr_split_2;
    end else begin
        active_mode = display_mode[15:8];
        base_fetch_addr1 = base_addr_1;
        base_fetch_addr2 = base_addr_2;
    end

    dma_addr_offset = 32'h00000000;

    dma_addr_offset[6:0] = screen_third_bias + screen_pos_horiz;
    if( active_mode[MODE__HIRES] )
        dma_addr_offset[12:10] = screen_pos_line_in_char;
    dma_addr_offset[9:7] = screen_pos_char_line_in_third;
end

task do_reset();
    current_x <= 0;
    current_y <= 0;
    screen_pos_horiz <= 0;
    screen_pos_vert <= SCREEN_LINES;    // Marks display_done until we're out of reset
    frame_x[PIPELINE_DMA] <= base_display_x;
    frame_y[PIPELINE_DMA] <= base_display_y;
    screen_third_bias <= 0;

    frame_data_valid[PIPELINE_DMA] <= 1'b0;
    frame_char_lookup_fill <= 0;
    frame_data_valid[PIPELINE_CHAR_LOOKUP] <= 1'b0;
    frame_data_valid[PIPELINE_CDC_CPU] <= 1'b0;
endtask

task advance_addr();
    screen_pos_horiz <= screen_pos_horiz + REQ_BUS_BYTES;
    current_x <= current_x + FETCH_PIXELS;

    if( screen_pos_horiz == SCREEN_LINE_BYTES - REQ_BUS_BYTES ) begin
        // Next line
        screen_pos_horiz <= 0;
        screen_pos_vert <= screen_pos_vert + 1;
        current_x <= 0;
        current_y <= current_y + Y_SPACING;

        if( screen_pos_vert[5:0] == 6'h3f ) begin
            // We're switching a third
            screen_third_bias <= screen_third_bias + SCREEN_LINE_BYTES;
        end
    end
endtask

logic pixel_cdc_valid_cpu = 1'b0, pixel_cdc_ack_cpi, pixel_cdc_valid_hdmi, pixel_cdc_ack_hdmi = 1'b0;

task do_cpu_cycle();
    if( !display_done && !frame_data_valid[PIPELINE_DMA] && !dma_req_sent ) begin
        // Initiate DMA fetch
        dma_req_valid_o <= 1'b1;
        dma_req_addr_o <= base_fetch_addr1 + dma_addr_offset;
        dma_req_sent <= 1'b1;

        frame_mode[PIPELINE_DMA] <= active_mode;
    end

    if( dma_req_valid_o && dma_req_ack_i )
        dma_req_valid_o <= 1'b0;

    if( dma_rsp_valid_i && dma_req_sent ) begin
        // Record DMA response
        frame_data[PIPELINE_DMA] <= dma_narrow_rsp_data;
        frame_data_valid[PIPELINE_DMA] <= 1'b1;
        dma_req_sent <= 1'b0;
    end

    if( frame_data_valid[PIPELINE_DMA] && !frame_data_valid[PIPELINE_CHAR_LOOKUP] ) begin
        // Move DMA stage data to next stage
        frame_data[PIPELINE_CHAR_LOOKUP] <= frame_data[PIPELINE_DMA];
        frame_x[PIPELINE_CHAR_LOOKUP] <= frame_x[PIPELINE_DMA] + current_x;
        frame_y[PIPELINE_CHAR_LOOKUP] <= frame_y[PIPELINE_DMA] + current_y;
        frame_mode[PIPELINE_CHAR_LOOKUP] <= frame_mode[PIPELINE_DMA];
        frame_char_lookup_line <= screen_pos_line_in_char;
        frame_char_lookup_fill <= REQ_BUS_BYTES;
        frame_data_valid[PIPELINE_CHAR_LOOKUP] <= 1'b1;

        frame_data_valid[PIPELINE_DMA] <= 1'b0;
        advance_addr();
    end

    if( frame_data_valid[PIPELINE_CHAR_LOOKUP] && !frame_data_valid[PIPELINE_CDC_CPU] && frame_char_lookup_fill!=0 ) begin
        // Shift down
        frame_data[PIPELINE_CHAR_LOOKUP] <= { 8'hXX, frame_data[PIPELINE_CHAR_LOOKUP][REQ_BUS_BITS-1:8] };
        frame_char_lookup_fill <= frame_char_lookup_fill - 1;
    end

    if( frame_data_valid[PIPELINE_CHAR_LOOKUP] && !frame_char_lookup_fill[3] ) begin
        // We have the lookup results ready
        frame_data[PIPELINE_CDC_CPU] <= { charrom_read_data, frame_data[PIPELINE_CDC_CPU][REQ_BUS_BITS-1:8] };

        if( frame_char_lookup_fill==0 ) begin
            frame_data_valid[PIPELINE_CHAR_LOOKUP] <= 1'b0;
            frame_data_valid[PIPELINE_CDC_CPU] <= 1'b1;
            frame_x[PIPELINE_CDC_CPU] <= frame_x[PIPELINE_CHAR_LOOKUP];
            frame_y[PIPELINE_CDC_CPU] <= frame_y[PIPELINE_CHAR_LOOKUP];
        end
    end

    if( frame_data_valid[PIPELINE_CDC_CPU] && !pixel_cdc_valid_cpu && !pixel_cdc_ack_cpu ) begin
        pixel_cdc_valid_cpu <= 1'b1;
    end

    if( frame_data_valid[PIPELINE_CDC_CPU] && pixel_cdc_valid_cpu && pixel_cdc_ack_cpu ) begin
        pixel_cdc_valid_cpu <= 1'b0;
        frame_data_valid[PIPELINE_CDC_CPU] <= 1'b0;
    end
endtask

logic prev_vsync = 1'b0;
always_ff@(posedge ctrl_clock_i) begin
    prev_vsync <= vsync_i;

    if( reset_i || (!vsync_i && vblank_i) )
        do_reset();
    else
        do_cpu_cycle();

    if( vsync_i && !prev_vsync )
        screen_pos_vert <= 0;
end

xpm_cdc_handshake#(
    .DEST_SYNC_FF(2),
    .SRC_SYNC_FF(2),
    .WIDTH(2*COORDINATE_WIDTH + REQ_BUS_BITS),
    .SIM_ASSERT_CHK(1)
) pixel_cdc(
    .src_clk(ctrl_clock_i),
    .src_in({frame_y[PIPELINE_CDC_CPU], frame_x[PIPELINE_CDC_CPU], frame_data[PIPELINE_CDC_CPU]}),
    .src_send(pixel_cdc_valid_cpu),
    .src_rcv(pixel_cdc_ack_cpu),

    .dest_clk(pixel_clock_i),
    .dest_out({frame_y[PIPELINE_CDC_HDMI], frame_x[PIPELINE_CDC_HDMI], frame_data[PIPELINE_CDC_HDMI]}),
    .dest_req(pixel_cdc_valid_hdmi),
    .dest_ack(pixel_cdc_ack_hdmi)
);

localparam BUFFER_PIXELS = FETCH_PIXELS;
wire [BUFFER_PIXELS-1:0] converted_pixel_cdc_data;
logic frame_data_out_valid;
logic [BUFFER_PIXELS-1:0] frame_data_out;
logic [$clog2(BUFFER_PIXELS+1)-1:0] frame_data_out_fill = 0;
logic [COORDINATE_WIDTH-1:0] frame_x_out, frame_y_out;

genvar i, j;
generate

for(j=0; j<REQ_BUS_BYTES; ++j) begin
    for(i=0; i<7; ++i) begin
        assign converted_pixel_cdc_data[j*14+2*i] = frame_data[PIPELINE_CDC_HDMI][j*8+i];
        assign converted_pixel_cdc_data[j*14+2*i+1] = frame_data[PIPELINE_CDC_HDMI][j*8+i];
    end
end

endgenerate

always_comb
    frame_data_out_valid = frame_data_out_fill!=0;

always_comb begin
    pixel_valid = frame_data_out_valid;
    pixel = frame_data_out[0] ? PIXEL_ON_COLOR : PIXEL_OFF_COLOR;
    pixel_x = frame_x_out;
    pixel_y = frame_y_out;
end

always_ff@(posedge pixel_clock_i) begin
    if( frame_data_out_valid && pixel_ack ) begin
        frame_data_out <= { 1'bX, frame_data_out[BUFFER_PIXELS-1:1] };
        frame_data_out_fill <= frame_data_out_fill - 1;
        frame_x_out <= frame_x_out + 1;
    end

    if( pixel_cdc_ack_hdmi && !pixel_cdc_valid_hdmi )
        pixel_cdc_ack_hdmi <= 1'b0;

    if( (!frame_data_out_valid || frame_data_out_fill==1) && pixel_cdc_valid_hdmi && !pixel_cdc_ack_hdmi ) begin
        frame_data_out <= converted_pixel_cdc_data;
        frame_data_out_fill <= BUFFER_PIXELS;
        frame_x_out <= frame_x[PIPELINE_CDC_HDMI];
        frame_y_out <= frame_y[PIPELINE_CDC_HDMI];

        pixel_cdc_ack_hdmi <= 1'b1;
    end
end

endmodule
