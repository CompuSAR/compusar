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

    output ctrl_irq_o,


    output dma_req_valid_o,
    output [31:0] dma_req_addr_o,
    output dma_req_write_o,
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

assign dma_req_valid_o = 1'b0;

logic sd_cmd_i, sd_cmd_o = 1'b1, sd_cmd_dir = 1'b1;

localparam CMDCDC_BITS = 2;
logic CMDCDC_ARG = 2'b01;
logic CMDCDC_CMD = 2'b00;

logic clock_selector = 1'b0;
logic [CMDCDC_BITS+31:0] cmd_cdc_data_ctrl, cmd_cdc_data_sd;
logic cmd_cdc_valid_ctrl = 1'b0, cmd_cdc_valid_sd, cmd_cdc_ack_ctrl, cmd_cdc_ack_sd = 1'b0;

// Only accept new commands if our CDC is idle
assign ctrl_req_ack_o = !cmd_cdc_valid_ctrl && !cmd_cdc_ack_ctrl;

localparam REPLY_ERROR_TIMEOUT = 4'b0001;
localparam REPLY_ERROR_CMD_MISMATCH = 4'b0010;
localparam REPLY_ERROR_CRC_MISMATCH = 4'b0100;
localparam REPLY_ERROR_INVALID_REPLY = 4'b1000;
localparam NUM_ERROR_BITS = 4;

logic status_busy = 1'b0, status_reply_received = 1'b0;
logic [NUM_ERROR_BITS-1:0] status_error = 4'b0000;
logic [127:0] last_reply_ctrl, cdc_reply_sd, cdc_reply_ctrl;
logic [NUM_ERROR_BITS-1:0] cdc_reply_error_sd, cdc_reply_error_ctrl;
logic cdc_reply_valid_ctrl, cdc_reply_valid_sd = 1'b0, cdc_reply_ack_sd;

// Handle ctrl commands
always_ff@(posedge ctrl_clock_i) begin
    ctrl_rsp_valid_o <= 1'b0;

    if( cdc_reply_valid_ctrl ) begin
        last_reply_ctrl <= cdc_reply_ctrl;
        status_error <= cdc_reply_error_ctrl;
        status_busy <= 1'b0;
        status_reply_received <= 1'b1;
    end

    if( cmd_cdc_valid_ctrl && cmd_cdc_ack_ctrl )
        cmd_cdc_valid_ctrl <= 1'b0;

    if( ctrl_req_valid_i && ctrl_req_ack_o ) begin
        if( ctrl_req_write_i ) begin
            // Handle the write case
            cmd_cdc_valid_ctrl <= 1'b1;
            case(ctrl_req_addr_i)
                16'h0000: cmd_cdc_data_ctrl <= { CMDCDC_ARG, ctrl_req_data_i };
                16'h0004: begin
                    cmd_cdc_data_ctrl <= { CMDCDC_CMD, ctrl_req_data_i };
                    status_reply_received <= 1'b0;
                    status_error <= 4'b0000;
                    status_busy <= ctrl_req_data_i[8];
                end
                default: cmd_cdc_valid_ctrl <= 1'b0;
            endcase
        end else begin
            // Handle the read case
            ctrl_rsp_valid_o <= 1'b1;
            case( ctrl_req_data_i )
                16'h0000: ctrl_rsp_data_o <= { status_busy, 23'b0, status_error, 3'b0, status_reply_received };
                16'h0010: ctrl_rsp_data_o <= last_reply_ctrl[31:0];
                16'h0014: ctrl_rsp_data_o <= last_reply_ctrl[63:32];
                16'h0018: ctrl_rsp_data_o <= last_reply_ctrl[95:64];
                16'h001c: ctrl_rsp_data_o <= last_reply_ctrl[127:96];
            endcase
        end
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
    .WIDTH(128+NUM_ERROR_BITS),
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

BUFGMUX clock_switcher(
    .I0(sd_default_speed_clock_i),
    .I1(sd_high_speed_clock_i),
    .S(clock_selector),

    .O(sd_clk)
);

assign sd_clk_o = sd_clk;

enum {
    CMD_IDLE = 4'b1000, CMD_SEND_CMD = 4'b0001, CMD_SEND_CRC = 4'b0010, CMD_RECV_PENDING = 4'b1001, CMD_RECV,
    CMD_RECV_CRC, CMD_RECV_STOP, CMD_RECV_ERR
 } cmd_state = CMD_IDLE;

localparam CMD_PAYLOAD_SIZE = 40;
localparam REPLY_PAYLOAD_SIZE = 128 + 6;
localparam REPLY_WAIT_CYCLES = 20;

wire cmd_crc_reset, cmd_crc_valid;
logic [31:0] cmd_args_sd;
logic [5:0] last_cmd_sd;
logic [1:0] reply_type_sd;
logic [REPLY_PAYLOAD_SIZE-1:0] cmd_io_buffer;
logic [$clog2(REPLY_PAYLOAD_SIZE+1)-1:0] cmd_io_buffer_fill;

assign cmd_crc_reset = cmd_state==CMD_IDLE || cmd_state==CMD_RECV_PENDING;
assign cmd_crc_valid = cmd_state==CMD_SEND_CMD || cmd_state==CMD_RECV;

localparam CMD_CRC_BITS = 7;
logic [CMD_CRC_BITS-1:0] cmd_crc_value;
localparam CMD_REPLY_BITS = 48 - CMD_CRC_BITS - 1;
localparam CMD_CMD_BITS = 40;

localparam START_BIT = 1'b0;
localparam STOP_BIT = 1'b1;

task handle_cmd_idle();
    if( cmd_cdc_valid_sd && !cmd_cdc_ack_sd ) begin
        cmd_cdc_ack_sd <= 1'b1;

        case(cmd_cdc_cmd)
            CMDCDC_ARG: cmd_args_sd <= cmd_cdc_data;
            CMDCDC_CMD: begin
                cmd_state <= CMD_SEND_CMD;
                cmd_io_buffer <= { START_BIT, 1'b1, cmd_cdc_data[5:0], cmd_args_sd };
                cmd_io_buffer_fill <= 39;
                last_cmd_sd <= cmd_cdc_data[5:0];
                reply_type_sd <= cmd_cdc_data[9:8];
            end
        endcase
    end
endtask

task handle_send_cmd();
    cmd_io_buffer[CMD_CMD_BITS-1:0] <= {cmd_io_buffer[CMD_CMD_BITS-2:0], 1'bX};
    cmd_io_buffer_fill <= cmd_io_buffer_fill - 1;

    if( cmd_io_buffer_fill==0 ) begin
        cmd_state <= CMD_SEND_CRC;
        cmd_io_buffer_fill <= CMD_CRC_BITS-1;
    end
endtask

task handle_send_crc();
    cmd_io_buffer[CMD_CMD_BITS-1:0] <= {cmd_io_buffer[CMD_CMD_BITS-2:0], 1'bX};
    cmd_io_buffer_fill <= cmd_io_buffer_fill - 1;

    if( cmd_io_buffer_fill==CMD_CRC_BITS-1 ) begin
        cmd_io_buffer[CMD_CMD_BITS:CMD_CMD_BITS-CMD_CRC_BITS] <= {1'bX, cmd_crc_value[CMD_CRC_BITS-2:0], 1'bX};
    end else if( cmd_io_buffer_fill==0 ) begin
        if( reply_type_sd==2'b00 )
            cmd_state <= CMD_IDLE;
        else begin
            cmd_state <= CMD_RECV_PENDING;
            cmd_io_buffer_fill <= REPLY_WAIT_CYCLES - 1;
        end
    end
endtask

task handle_recv_pend();
    cmd_io_buffer_fill <= cmd_io_buffer_fill - 1;

    if( sd_cmd_i == 1'b0 ) begin
        cmd_state <= CMD_RECV;
        cmd_io_buffer_fill <= CMD_REPLY_BITS - 2;       // -1 for the non-blocking assignment, another because this cycle should also count
        cmd_io_buffer[0] <= 1'b0;

        // Our CRC calculation doesn't look at this start bit. That's okay,
        // however, as the CRC's initial value is 0, which means it is
        // agnostic to leading zeros.
    end else if( cmd_io_buffer_fill==0 ) begin
        cdc_reply_error_sd <= REPLY_ERROR_TIMEOUT;
        cdc_reply_valid_sd <= 1'b1;
        cmd_state <= CMD_IDLE;
    end
endtask

task handle_recv();
    cmd_io_buffer_fill <= cmd_io_buffer_fill - 1;
    cmd_io_buffer[47:0] <= { cmd_io_buffer[46:0], sd_cmd_i };

    if( cmd_io_buffer_fill == 0 ) begin
        cmd_state <= CMD_RECV_CRC;
        cmd_io_buffer_fill <= CMD_CRC_BITS - 1;
    end
endtask

task handle_recv_crc();
    cmd_io_buffer_fill <= cmd_io_buffer_fill - 1;
    cmd_io_buffer[47:0] <= { cmd_io_buffer[46:0], sd_cmd_i };

    if( cmd_io_buffer_fill == 0 ) begin
        cmd_state <= CMD_RECV_STOP;
    end
endtask

task handle_recv_stop();
    automatic logic [NUM_ERROR_BITS-1:0] error = 0;

    cmd_state <= CMD_IDLE;

    if( sd_cmd_i != 1'b1 )
        error |= REPLY_ERROR_INVALID_REPLY;
    if( cmd_io_buffer[CMD_CRC_BITS+37:CMD_CRC_BITS+32] != last_cmd_sd )
        error |= REPLY_ERROR_CMD_MISMATCH;
    if( cmd_io_buffer[CMD_CRC_BITS-1:0] != cmd_crc_value )
        error |= REPLY_ERROR_CRC_MISMATCH;

    cdc_reply_error_sd <= error;
    cdc_reply_valid_sd <= 1'b1;

    cdc_reply_sd[31:0] <= cmd_io_buffer[CMD_CRC_BITS+31:CMD_CRC_BITS];
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
        CMD_RECV_PENDING: handle_recv_pend();
        CMD_RECV: handle_recv();
        CMD_RECV_CRC: handle_recv_crc();
        CMD_RECV_STOP: handle_recv_stop();
    endcase
end

always_ff@(negedge sd_clk) begin
    sd_cmd_o <= cmd_io_buffer[CMD_CMD_BITS-1];
    if( cmd_state==CMD_SEND_CRC && cmd_io_buffer_fill==CMD_CRC_BITS-1 )
        sd_cmd_o <= cmd_crc_value[CMD_CRC_BITS-1];

    sd_cmd_dir <= cmd_state[3];
end

crc#(
    .CRC_BITS(CMD_CRC_BITS),
    .INIT_VALUE(7'b0),
    .POLYNOM(7'b0001001)
) cmd_crc(
    .clock_i(sd_clk),
    .reset_i(cmd_crc_reset),
    .bit_valid_i(cmd_crc_valid),
    .bit_i(sd_cmd_dir ? sd_cmd_i : sd_cmd_o),

    .crc_o(cmd_crc_value)
);

/*
crc#(
    .CRC_BITS(16),
    .INIT_VALUE(7'b0),
    .POLYNOM(16'b0001000000100001)
) data_crc(
    .clock_i(sd_clk),
    .reset_i(reset),
    .bit_valid_i(valid16),
    .bit_i(value),

    .crc_o(current_crc16)
);
*/

IOBUF cmd_buf(
    .I(sd_cmd_o),
    .O(sd_cmd_i),
    .T(sd_cmd_dir),

    .IO(sd_cmd_io)
);

endmodule
