`timescale 1ns / 1ps

module sd#(
    DMA_WIDTH = 128
)(
    input ctrl_clock_i,
    input reset_i,

    input ctrl_req_valid_i,
    input [15:0] ctrl_req_addr_i,
    input ctrl_req_write_i,
    input [31:0] ctrl_req_data_i,
    output ctrl_req_ack_o,

    output logic ctrl_rsp_valid_o = 1'b0,
    output logic [31:0] ctrl_rsp_data_o,

    output ctrl_data_idle_irq_o,


    output logic dma_req_valid_o = 1'b0,
    output logic [31:0] dma_req_addr_o,
    output logic dma_req_write_o,
    output [DMA_WIDTH-1:0] dma_req_data_o,
    input dma_req_ack_i,

    input dma_rsp_valid_i,
    input [DMA_WIDTH-1:0] dma_rsp_data_i,


    input sd_default_speed_clock_i,
    input sd_high_speed_clock_i,

    inout sd_cmd_io,
    inout [3:0] sd_data_io,
    output sd_clk_o
);

logic sd_cmd_i, sd_cmd_o = 1'b1, sd_cmd_dir = 1'b1;

localparam DMA_WIDTH_BYTES = DMA_WIDTH / 8;

localparam CMDCDC_BITS = 2;
//logic [CMDCDC_BITS-1:0] CMDCDC_ARG = 2'b01, CMDCDC_CMD = 2'b00, CMDCDC_DATA = 2'b10;
localparam CMDCDC_ARG = 2'b01, CMDCDC_CMD = 2'b00, CMDCDC_DATA = 2'b10;

localparam MAX_DATA_TRANSFER = 2048;
localparam MAX_DATA_TRANSFER_BITS = $clog2(MAX_DATA_TRANSFER + 1);
localparam DATA_START_WAIT_TIMEOUT = 25000;     // Give the card 1ms to respond
localparam DATA_CRC_BITS = 16;

localparam SD_CDC_PIPELINE_LEN = 4;

logic clock_selector = 1'b0;
logic [CMDCDC_BITS+31:0] cmd_cdc_data_ctrl;
logic cmd_cdc_valid_ctrl = 1'b0, cmd_cdc_valid_sd, cmd_cdc_ack_ctrl, cmd_cdc_ack_sd = 1'b0;

logic [DMA_WIDTH-1:0] data_cdc_data_sd;
logic data_cdc_valid_ctrl, data_cdc_valid_sd, data_cdc_ack_ctrl = 1'b0, data_cdc_ack_sd;

// Only accept new commands if our CDC is idle
assign ctrl_req_ack_o = !cmd_cdc_valid_ctrl && !cmd_cdc_ack_ctrl;

localparam REPLY_ERROR_TIMEOUT = 4'b0001;
localparam REPLY_ERROR_CMD_MISMATCH = 4'b0010;
localparam REPLY_ERROR_CRC_MISMATCH = 4'b0100;
localparam REPLY_ERROR_INVALID_REPLY = 4'b1000;
localparam NUM_CMD_ERROR_BITS = 4;

localparam NUM_DATA_ERROR_BITS = 5;

logic status_cmd_busy = 1'b0, status_reply_received = 1'b0;
logic [NUM_CMD_ERROR_BITS-1:0] status_cmd_error = 4'b0000;
logic [127:0] last_reply_ctrl, cdc_reply_sd, cdc_reply_ctrl;
logic [NUM_CMD_ERROR_BITS-1:0] cdc_reply_error_sd, cdc_reply_error_ctrl;
logic cdc_reply_valid_ctrl, cdc_reply_valid_sd = 1'b0, cdc_reply_ack_sd;

logic status_data_busy, status_data_started = 1'b0, status_data_active;
assign status_data_busy = status_data_started || status_data_active;
assign ctrl_data_idle_irq_o = !status_data_busy;

logic [NUM_DATA_ERROR_BITS-1:0] status_data_error;

logic [31:0]  dma_address;

always_ff@(posedge ctrl_clock_i) begin
    // Handle ctrl commands
    ctrl_rsp_valid_o <= 1'b0;

    if( cdc_reply_valid_ctrl ) begin
        last_reply_ctrl <= cdc_reply_ctrl;
        status_cmd_error <= cdc_reply_error_ctrl;
        status_cmd_busy <= 1'b0;
        status_reply_received <= 1'b1;
    end

    if( cmd_cdc_valid_ctrl && cmd_cdc_ack_ctrl )
        cmd_cdc_valid_ctrl <= 1'b0;

    if( status_data_started && status_data_active )
        status_data_started <= 1'b0;

    if( ctrl_req_valid_i && ctrl_req_ack_o ) begin
        if( ctrl_req_write_i ) begin
            // Handle the write case
            cmd_cdc_valid_ctrl <= 1'b1;
            case(ctrl_req_addr_i)
                16'h0000: begin
                    cmd_cdc_data_ctrl <= { CMDCDC_ARG, ctrl_req_data_i };
                    cmd_cdc_valid_ctrl <= 1'b1;
                end
                16'h0004: begin
                    cmd_cdc_data_ctrl <= { CMDCDC_CMD, ctrl_req_data_i };
                    cmd_cdc_valid_ctrl <= 1'b1;
                    status_reply_received <= 1'b0;
                    status_cmd_error <= 4'b0000;
                    status_cmd_busy <= ctrl_req_data_i[8];
                end
                16'h0100: begin
                    dma_address <= ctrl_req_data_i;
                end
                16'h0104: begin
                    cmd_cdc_data_ctrl <= { CMDCDC_DATA, ctrl_req_data_i };
                    cmd_cdc_valid_ctrl <= 1'b1;
                end
            endcase
        end else begin
            // Handle the read case
            ctrl_rsp_valid_o <= 1'b1;
            case( ctrl_req_addr_i )
                16'h0000: ctrl_rsp_data_o <= {
                    status_cmd_busy, status_data_busy, 6'b0,
                    3'b0, status_data_error,
                    8'b0,
                    status_cmd_error, 3'b0, status_reply_received };
                16'h0010: ctrl_rsp_data_o <= last_reply_ctrl[31:0];
                16'h0014: ctrl_rsp_data_o <= last_reply_ctrl[63:32];
                16'h0018: ctrl_rsp_data_o <= last_reply_ctrl[95:64];
                16'h001c: ctrl_rsp_data_o <= last_reply_ctrl[127:96];
            endcase
        end
    end

    // Handle the read DMA case
    if( !data_cdc_valid_ctrl && data_cdc_ack_ctrl )
        data_cdc_ack_ctrl <= 1'b0;

    if( data_cdc_valid_ctrl && !data_cdc_ack_ctrl && !dma_req_valid_o ) begin
        dma_req_valid_o <= 1'b1;
        dma_req_addr_o <= dma_address;
        dma_req_write_o <= 1'b1;
    end

    if( data_cdc_valid_ctrl && !data_cdc_ack_ctrl && dma_req_valid_o && dma_req_ack_i ) begin
        dma_req_valid_o <= 1'b0;
        data_cdc_ack_ctrl <= 1'b1;
        dma_address <= dma_address + DMA_WIDTH_BYTES;
    end
end

wire sd_clk;
wire [CMDCDC_BITS-1:0] cmd_cdc_cmd;
wire [31:0] cmd_cdc_data;
xpm_cdc_handshake#(
    .WIDTH(32+CMDCDC_BITS),
    .SRC_SYNC_FF(2),
    .DEST_SYNC_FF(2)
) cmd_cdc(
    .src_clk(ctrl_clock_i),
    .src_in(cmd_cdc_data_ctrl),
    .src_rcv(cmd_cdc_ack_ctrl),
    .src_send(cmd_cdc_valid_ctrl),

    .dest_clk(sd_clk),
    .dest_req(cmd_cdc_valid_sd),
    .dest_out({cmd_cdc_cmd, cmd_cdc_data}),
    .dest_ack(cmd_cdc_ack_sd)
);

xpm_cdc_handshake#(
    .WIDTH(128+NUM_CMD_ERROR_BITS),
    .SRC_SYNC_FF(2),
    .DEST_SYNC_FF(2),
    .DEST_EXT_HSK(0)
) cmd_reply_cdc(
    .src_clk(sd_clk),
    .src_in({cdc_reply_error_sd, cdc_reply_sd}),
    .src_send(cdc_reply_valid_sd),
    .src_rcv(cdc_reply_ack_sd),

    .dest_clk(ctrl_clock_i),
    .dest_out({cdc_reply_error_ctrl, cdc_reply_ctrl}),
    .dest_req(cdc_reply_valid_ctrl)
);

xpm_cdc_handshake#(
    .WIDTH(DMA_WIDTH),
    .SRC_SYNC_FF(2),
    .DEST_SYNC_FF(2)
) data_cdc_read(
    .src_clk(sd_clk),
    .src_in(data_cdc_data_sd),
    .src_send(data_cdc_valid_sd),
    .src_rcv(data_cdc_ack_sd),

    .dest_clk(ctrl_clock_i),
    .dest_out(dma_req_data_o),
    .dest_req(data_cdc_valid_ctrl),
    .dest_ack(data_cdc_ack_ctrl)
);

/*
BUFGMUX clock_switcher(
    .I0(sd_default_speed_clock_i),
    .I1(sd_high_speed_clock_i),
    .S(clock_selector),

    .O(sd_clk)
);
*/
assign sd_clk = sd_default_speed_clock_i;

assign sd_clk_o = sd_clk;

enum logic[3:0] {
    CMD_IDLE = 4'b0100, CMD_SEND_CMD = 4'b0001, CMD_SEND_CRC = 4'b0010, CMD_SEND_STOP = 4'b0111,
    CMD_RECV_PENDING = 4'b1000, CMD_RECV_HEADER, CMD_RECV_DATA, CMD_RECV_CRC, CMD_RECV_STOP
 } cmd_state = CMD_IDLE;

localparam CMD_PAYLOAD_SIZE = 40;
localparam REPLY_PAYLOAD_SIZE = 128 + 6;
localparam REPLY_WAIT_CYCLES = 20;

wire cmd_crc_reset, cmd_crc_valid;
wire [6:0] cmd_crc_init_value;
logic [31:0] cmd_args_sd;
logic [5:0] last_cmd_sd;
logic [1:0] reply_type_sd;
logic [REPLY_PAYLOAD_SIZE-1:0] cmd_io_buffer;
logic [$clog2(REPLY_PAYLOAD_SIZE+1)-1:0] cmd_io_buffer_fill;

assign cmd_crc_reset = cmd_state==CMD_IDLE || cmd_state==CMD_RECV_PENDING;
assign cmd_crc_valid = cmd_state==CMD_SEND_CMD || cmd_state==CMD_RECV_HEADER || cmd_state==CMD_RECV_DATA;
// In case of 136bit answer (R2), initialize the CRC so that it zeros after the
// header, which is always 8'b00111111.
assign cmd_crc_init_value = (cmd_state==CMD_RECV_PENDING && cmd_cdc_data[9]) ? 7'b0111111 : 7'b0000000;

localparam CMD_CRC_BITS = 7;
localparam CMD_REPLY_HEADER_BITS = 8;
logic [CMD_CRC_BITS-1:0] cmd_crc_value;
localparam CMD_REPLY_BITS = 48 - CMD_CRC_BITS - 1;
localparam CMD_REPLY_BITS_LONG = 136 - CMD_CRC_BITS - 1;
localparam CMD_CMD_BITS = 40;

logic [MAX_DATA_TRANSFER_BITS-1:0] sd_data_bits_counter;
logic [DMA_WIDTH-1:0] data_pipeline[SD_CDC_PIPELINE_LEN];
logic [DMA_WIDTH-1:0] data_buffer;
logic [$clog2(DATA_START_WAIT_TIMEOUT)-1:0] data_buffer_fill;
logic data_pipeline_valid[SD_CDC_PIPELINE_LEN];
assign data_cdc_valid_sd = data_pipeline_valid[0];
logic sd_data_error_start_bit = 1'b0, sd_data_error_stop_bit = 1'b0, sd_data_error_crc = 1'b0, sd_data_error_timeout = 1'b0,
    sd_data_error_pipeline_overrun = 1'b0;

initial begin
    for( int i=0; i<SD_CDC_PIPELINE_LEN; ++i )
        data_pipeline_valid[i] = 1'b0;
end

localparam START_BIT = 1'b0;
localparam STOP_BIT = 1'b1;

logic [3:0] sd_data_i, sd_data_o;
logic sd_data_dir = 1'b1, sd_data_width_4bit = 1'b0;
logic [DATA_CRC_BITS-1:0] data_crc_value[4];

enum {
    DATA_IDLE, DATA_R_WAIT_START, DATA_RECV, DATA_R_CRC, DATA_R_STOP
 } data_state = DATA_IDLE;

genvar i;

generate

for( i=0; i<4; ++i ) begin : data_channels
    IOBUF data_buf(
        .I(sd_data_o[i]),
        .O(sd_data_i[i]),
        .T(sd_data_dir),

        .IO(sd_data_io[i])
    );

    crc#(
        .CRC_BITS(DATA_CRC_BITS),
        .POLYNOM(16'b0001000000100001)
    ) data_crc(
        .clock_i(sd_clk),
        .reset_i(data_state == DATA_IDLE),
        .bit_valid_i(data_state == DATA_RECV),
        .bit_i(sd_data_dir ? sd_data_i[i] : sd_data_o[i]),
        .init_value_i(16'h0000),

        .crc_o(data_crc_value[i])
    );
end : data_channels

// Reverse the byte order when sendin the data to the CDC
for( i=0; i<DMA_WIDTH_BYTES; ++i ) begin
    assign data_cdc_data_sd[i*8+7:i*8] = data_pipeline[0][(DMA_WIDTH_BYTES-i)*8-1:(DMA_WIDTH_BYTES-i-1)*8];
end

endgenerate

task handle_cmd_idle();
    if( cmd_cdc_valid_sd && !cmd_cdc_ack_sd ) begin
        cmd_cdc_ack_sd <= 1'b1;

        case(cmd_cdc_cmd)
            CMDCDC_ARG: cmd_args_sd <= cmd_cdc_data;
            CMDCDC_CMD: begin
                cmd_state <= CMD_SEND_CMD;
                cmd_io_buffer <= { {REPLY_PAYLOAD_SIZE-48{1'bX}}, START_BIT, 1'b1, cmd_cdc_data[5:0], cmd_args_sd };
                cmd_io_buffer_fill <= 39;
                if( cmd_cdc_data[10] )
                    last_cmd_sd <= 6'b111111;
                else
                    last_cmd_sd <= cmd_cdc_data[5:0];
                reply_type_sd <= cmd_cdc_data[9:8];

                // TODO look at cmd_cdc_data[13] for DATA write support
                if( data_state==DATA_IDLE && cmd_cdc_data[12] ) begin
                    data_state <= DATA_R_WAIT_START;
                    sd_data_error_start_bit <= 1'b0;
                    sd_data_error_stop_bit <= 1'b0;
                    sd_data_error_crc <= 1'b0;
                    sd_data_error_timeout <= 1'b0;
                    sd_data_error_pipeline_overrun <= 1'b0;
                    data_buffer_fill <= DATA_START_WAIT_TIMEOUT;
                end
            end
            CMDCDC_DATA: begin
                sd_data_bits_counter <= cmd_cdc_data[MAX_DATA_TRANSFER_BITS-1:0];
                sd_data_width_4bit <= cmd_cdc_data[31];
                for( int i=0; i<SD_CDC_PIPELINE_LEN; ++i )
                    data_pipeline_valid[i] <= 1'b0;
            end
        endcase
    end
endtask

task handle_send_cmd();
    cmd_io_buffer <= { cmd_io_buffer[REPLY_PAYLOAD_SIZE-2:0], 1'bX };
    cmd_io_buffer_fill <= cmd_io_buffer_fill - 1;

    if( cmd_io_buffer_fill==0 ) begin
        cmd_state <= CMD_SEND_CRC;
        cmd_io_buffer_fill <= CMD_CRC_BITS-1;
    end
endtask

task handle_send_crc();
    cmd_io_buffer <= { cmd_io_buffer[REPLY_PAYLOAD_SIZE-2:0], 1'bX };
    cmd_io_buffer_fill <= cmd_io_buffer_fill - 1;

    if( cmd_io_buffer_fill==CMD_CRC_BITS-1 ) begin
        cmd_io_buffer[CMD_CMD_BITS:CMD_CMD_BITS-CMD_CRC_BITS] <= {1'bX, cmd_crc_value[CMD_CRC_BITS-2:0], 1'bX};
    end else if( cmd_io_buffer_fill==0 ) begin
        cmd_state <= CMD_SEND_STOP;
    end
endtask

task handle_send_stop();
    if( reply_type_sd==2'b00 )
        cmd_state <= CMD_IDLE;
    else begin
        cmd_state <= CMD_RECV_PENDING;
        cmd_io_buffer_fill <= REPLY_WAIT_CYCLES - 1;
    end
endtask

task handle_recv_pend();
    cmd_io_buffer_fill <= cmd_io_buffer_fill - 1;
    cdc_reply_error_sd <= { NUM_CMD_ERROR_BITS{1'b0} };

    if( sd_cmd_i == 1'b0 ) begin
        cmd_state <= CMD_RECV_HEADER;
        cmd_io_buffer_fill <= 6;        // 1 start bit (already passed), 1 direction bit (non-blocking assignment) and 6 cmd bits
        cmd_io_buffer[0] <= sd_cmd_i;

        // Our CRC calculation doesn't look at this start bit. That's okay,
        // however, as the CRC's initial value is 0, which means it is
        // agnostic to leading zeros. It's more problematic for 136 bit
        // replies, but there we just seed the initial value considering this
        // fact.
    end else if( cmd_io_buffer_fill==0 ) begin
        cdc_reply_error_sd <= REPLY_ERROR_TIMEOUT;
        cdc_reply_valid_sd <= 1'b1;
        cmd_state <= CMD_IDLE;
    end
endtask

task handle_recv_header();
    cmd_io_buffer_fill <= cmd_io_buffer_fill - 1;
    cmd_io_buffer <= { cmd_io_buffer[REPLY_PAYLOAD_SIZE-2:0], sd_cmd_i };

    if( cmd_io_buffer_fill == 0 ) begin
        cmd_state <= CMD_RECV_DATA;

        if( cmd_cdc_data[9] ) begin
            // 136 bit reply

            // -1 for the non-blocking assignment, another because this cycle should also count
            cmd_io_buffer_fill <= CMD_REPLY_BITS_LONG - CMD_REPLY_HEADER_BITS - 1;
        end else begin
            // Regular 48 bit reply
            cmd_io_buffer_fill <= CMD_REPLY_BITS  - CMD_REPLY_HEADER_BITS - 1;
        end

        if( {cmd_io_buffer[4:0], sd_cmd_i} != last_cmd_sd ) begin
            cdc_reply_error_sd <= REPLY_ERROR_CMD_MISMATCH;
        end
    end
endtask

task handle_recv_data();
    cmd_io_buffer_fill <= cmd_io_buffer_fill - 1;
    cmd_io_buffer <= { cmd_io_buffer[REPLY_PAYLOAD_SIZE-2:0], sd_cmd_i };

    if( cmd_io_buffer_fill == 0 ) begin
        cmd_state <= CMD_RECV_CRC;
        cmd_io_buffer_fill <= CMD_CRC_BITS - 1;
    end
endtask

task handle_recv_crc();
    cmd_io_buffer_fill <= cmd_io_buffer_fill - 1;
    cmd_io_buffer <= { cmd_io_buffer[REPLY_PAYLOAD_SIZE-2:0], sd_cmd_i };

    if( cmd_io_buffer_fill == 0 ) begin
        cmd_state <= CMD_RECV_STOP;
    end
endtask

task handle_recv_stop();
    automatic logic [NUM_CMD_ERROR_BITS-1:0] error = 0;

    cmd_state <= CMD_IDLE;

    if( sd_cmd_i != 1'b1 )
        error |= REPLY_ERROR_INVALID_REPLY;
    if( cmd_io_buffer[CMD_CRC_BITS-1:0] != cmd_crc_value )
        error |= REPLY_ERROR_CRC_MISMATCH;

    cdc_reply_error_sd <= cdc_reply_error_sd | error;
    cdc_reply_valid_sd <= 1'b1;

    if( cmd_cdc_data[9] ) begin
        cdc_reply_sd <= { cmd_io_buffer[126:0], sd_cmd_i };
    end else begin
        cdc_reply_sd <= { 96'bX, cmd_io_buffer[CMD_CRC_BITS+31:CMD_CRC_BITS] };
    end
endtask

task handle_data_idle();
endtask

task handle_data_r_wait_start();

    if( sd_data_i[0] == START_BIT ) begin
        sd_data_bits_counter <= sd_data_bits_counter - 1;

        data_state <= DATA_RECV;
        data_buffer_fill <= 0;

        if( sd_data_width_4bit && sd_data_i != 4'b0000 )
            sd_data_error_start_bit <= 1'b1;
    end else begin
        data_buffer_fill <= data_buffer_fill - 1;
        if( data_buffer_fill==0 ) begin
            sd_data_error_timeout <= 1'b1;
            data_state <= DATA_IDLE;
        end
    end
endtask

task handle_data_receive();
    sd_data_bits_counter <= sd_data_bits_counter - 1;
    if( sd_data_bits_counter==0 ) begin
        data_state <= DATA_R_CRC;
        sd_data_bits_counter <= DATA_CRC_BITS - 1;
    end

    if( sd_data_width_4bit ) begin
        $display("4 bit receive not yet implemented");
    end else begin
        data_buffer <= {data_buffer[DMA_WIDTH-2:0], sd_data_i[0]};
        data_buffer_fill <= data_buffer_fill + 1;

        if( data_buffer_fill==DMA_WIDTH-1 ) begin
            data_buffer_fill <= 0;
            data_pipeline[SD_CDC_PIPELINE_LEN-1] <= {data_buffer[DMA_WIDTH-2:0], sd_data_i[0]};
            data_pipeline_valid[SD_CDC_PIPELINE_LEN-1] <= 1'b1;

            if( data_pipeline_valid[SD_CDC_PIPELINE_LEN-1] ) begin
                sd_data_error_pipeline_overrun <= 1'b1;
            end
        end
    end
endtask

task handle_data_r_crc();
    sd_data_bits_counter <= sd_data_bits_counter - 1;

    if( sd_data_i[0] != data_crc_value[0][sd_data_bits_counter] )
        sd_data_error_crc <= 1'b1;

    if( sd_data_width_4bit ) begin
        for( int i=1; i<4; ++i ) begin
            if( sd_data_i[i] != data_crc_value[i][sd_data_bits_counter] )
                sd_data_error_crc <= 1'b1;
        end
    end

    if( sd_data_bits_counter==0 )
        data_state <= DATA_R_STOP;
endtask

task handle_data_r_stop();
    if( sd_data_i[0] != 1'b1 )
        sd_data_error_stop_bit <= 1'b1;

    if( sd_data_width_4bit ) begin
        for( int i=1; i<4; ++i ) begin
            if( sd_data_i[i] != 1'b1 )
                sd_data_error_stop_bit <= 1'b1;
        end
    end

    data_state <= DATA_IDLE;
endtask

always_ff@(posedge sd_clk) begin
    if( cmd_cdc_ack_sd && !cmd_cdc_valid_sd )
        cmd_cdc_ack_sd <= 1'b0;

    if( cdc_reply_valid_sd && cdc_reply_ack_sd )
        cdc_reply_valid_sd <= 1'b0;

    case( cmd_state )
        CMD_IDLE: handle_cmd_idle();
        CMD_SEND_CMD: handle_send_cmd();
        CMD_SEND_CRC: handle_send_crc();
        CMD_SEND_STOP: handle_send_stop();
        CMD_RECV_PENDING: handle_recv_pend();
        CMD_RECV_HEADER: handle_recv_header();
        CMD_RECV_DATA: handle_recv_data();
        CMD_RECV_CRC: handle_recv_crc();
        CMD_RECV_STOP: handle_recv_stop();
    endcase

    // Advance the data pipeline
    // TODO this handles only the read path
    for( int i=2; i<SD_CDC_PIPELINE_LEN; ++i ) begin
        if( data_pipeline_valid[i] && !data_pipeline_valid[i-1] ) begin
            data_pipeline[i-1] <= data_pipeline[i];
            data_pipeline_valid[i-1] <= 1'b1;
            data_pipeline_valid[i] <= 1'b0;
        end
    end

    if( data_pipeline_valid[1] && !data_pipeline_valid[0] && !data_cdc_ack_sd ) begin
        data_pipeline[0] <= data_pipeline[1];
        data_pipeline_valid[0] <= 1'b1;
        data_pipeline_valid[1] <= 1'b0;
    end

    if( data_pipeline_valid[0] && data_cdc_ack_sd ) begin
        data_pipeline_valid[0] <= 1'b0;
    end

    case( data_state )
        DATA_IDLE: handle_data_idle();
        DATA_R_WAIT_START: handle_data_r_wait_start();
        DATA_RECV: handle_data_receive();
        DATA_R_CRC: handle_data_r_crc();
        DATA_R_STOP: handle_data_r_stop();
    endcase
end

always_ff@(negedge sd_clk) begin
    sd_cmd_o <= cmd_io_buffer[CMD_CMD_BITS-1];
    if( cmd_state==CMD_SEND_CRC && cmd_io_buffer_fill==CMD_CRC_BITS-1 )
        sd_cmd_o <= cmd_crc_value[CMD_CRC_BITS-1];
    if( cmd_state[2] )
        sd_cmd_o <= 1'b1;

    sd_cmd_dir <= cmd_state[3];
end

crc#(
    .CRC_BITS(CMD_CRC_BITS),
    .POLYNOM(7'b0001001)
) cmd_crc(
    .clock_i(sd_clk),
    .reset_i(cmd_crc_reset),
    .bit_valid_i(cmd_crc_valid),
    .bit_i(sd_cmd_dir ? sd_cmd_i : sd_cmd_o),
    .init_value_i(cmd_crc_init_value),

    .crc_o(cmd_crc_value)
);

xpm_cdc_array_single#(
    .WIDTH(NUM_DATA_ERROR_BITS + 1)
) data_cdc_status(
    .src_clk(sd_clk),
    .src_in({data_state!=DATA_IDLE, sd_data_error_pipeline_overrun, sd_data_error_start_bit, sd_data_error_stop_bit, sd_data_error_crc, sd_data_error_timeout}),

    .dest_clk(ctrl_clock_i),
    .dest_out({status_data_active, status_data_error})
);

IOBUF cmd_buf(
    .I(sd_cmd_o),
    .O(sd_cmd_i),
    .T(sd_cmd_dir),

    .IO(sd_cmd_io)
);

endmodule
