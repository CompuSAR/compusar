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

    output logic ctrl_rsp_valid_o,
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

// Handle ctrl commands
always_ff@(posedge ctrl_clock_i) begin
    ctrl_rsp_valid_o <= 1'b0;

    if( cmd_cdc_valid_ctrl && cmd_cdc_ack_ctrl )
        cmd_cdc_valid_ctrl <= 1'b0;

    if( ctrl_req_valid_i && ctrl_req_ack_o ) begin
        if( ctrl_req_write_i ) begin
            // Handle the write case
            cmd_cdc_valid_ctrl <= 1'b1;
            case(ctrl_req_addr_i)
                16'h0000: cmd_cdc_data_ctrl <= { CMDCDC_ARG, ctrl_req_data_i };
                16'h0004: cmd_cdc_data_ctrl <= { CMDCDC_CMD, ctrl_req_data_i };
                default: cmd_cdc_valid_ctrl <= 1'b0;
            endcase
        end else begin
            // Handle the read case
            ctrl_rsp_valid_o <= 1'b1;
        end
    end
end

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

wire sd_clk;
BUFGMUX clock_switcher(
    .I0(sd_default_speed_clock_i),
    .I1(sd_high_speed_clock_i),
    .S(clock_selector),

    .O(sd_clk)
);
assign sd_clk_o = sd_clk;

enum { CMD_IDLE, CMD_SEND_CMD, CMD_SEND_CRC } cmd_state = CMD_IDLE;
wire cmd_crc_reset, cmd_crc_valid;
logic [31:0] cmd_args_sd;
logic [39:0] cmd_io_buffer;
logic [$clog2(40+1)-1:0] cmd_io_buffer_fill;

assign cmd_crc_reset = cmd_state==CMD_IDLE;
assign cmd_crc_valid = cmd_state==CMD_SEND_CMD;

localparam CMD_CRC_BITS = 7;
logic [CMD_CRC_BITS-1:0] cmd_crc_value;

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
            end
        endcase
    end
endtask

task handle_send_cmd();
    if( cmd_io_buffer_fill==0 ) begin
        cmd_state <= CMD_SEND_CRC;
        cmd_io_buffer[39:33] <= cmd_crc_value;
        cmd_io_buffer_fill <= CMD_CRC_BITS-1;
    end
endtask

task handle_send_crc();
    if( cmd_io_buffer_fill==0 ) begin
        cmd_state <= CMD_IDLE;
    end
endtask

always_ff@(posedge sd_clk) begin
    if( cmd_cdc_ack_sd && !cmd_cdc_valid_sd )
        cmd_cdc_ack_sd <= 1'b0;

    if( cmd_state!=CMD_IDLE ) begin
        cmd_io_buffer <= {cmd_io_buffer[38:0], 1'bX};
        cmd_io_buffer_fill <= cmd_io_buffer_fill - 1;
    end

    case( cmd_state )
        CMD_IDLE: handle_cmd_idle();
        CMD_SEND_CMD: handle_send_cmd();
        CMD_SEND_CRC: handle_send_crc();
    endcase
end

always_ff@(negedge sd_clk) begin
    sd_cmd_o <= cmd_io_buffer[39];
    sd_cmd_dir <= cmd_state == CMD_IDLE;
end

crc#(
    .CRC_BITS(CMD_CRC_BITS),
    .INIT_VALUE(7'b0),
    .POLYNOM(7'b0001001)
) cmd_crc(
    .clock_i(!sd_clk),
    .reset_i(cmd_crc_reset),
    .bit_valid_i(cmd_crc_valid),
    .bit_i(cmd_io_buffer[39]),

    .crc_o(cmd_crc_value)
);

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

IOBUF cmd_buf(
    .I(sd_cmd_o),
    .O(sd_cmd_i),
    .T(sd_cmd_dir),

    .IO(sd_cmd_io)
);

endmodule
