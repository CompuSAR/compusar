`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/10/2026 09:12:35 PM
// Design Name: 
// Module Name: sd_sim_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module sd_sim_top(
    );

logic sd_clk_default, sd_clk_high, ctrl_clk;

initial begin
    // 25MHz clock
    sd_clk_default = 1'b0;
    forever begin
        #20 sd_clk_default = 1'b1;
        #20 sd_clk_default = 1'b0;
    end
end

initial begin
    // 50MHz clock
    sd_clk_high = 1'b0;
    forever begin
        #10 sd_clk_high = 1'b1;
        #10 sd_clk_high = 1'b0;
    end
end

initial begin
    // ~75MHz clock
    ctrl_clk = 1'b0;
    forever begin
        #6.598 ctrl_clk = 1'b1;
        #6.598 ctrl_clk = 1'b0;
    end
end

logic req_valid = 1'b0, req_ack, req_write, rsp_valid;
logic [15:0] req_addr;
logic [31:0] req_data, rsp_data;

logic sd_cmd_drive = 1'bz;
wire sd_cmd_pin, sd_cmd_signal;
assign sd_cmd_pin = sd_cmd_drive;
assign sd_cmd_signal = sd_cmd_pin === 1'bZ ? 1'b1 : sd_cmd_pin;
wire sd_clock;

sd sd(
    .ctrl_clock_i(ctrl_clk),

    .ctrl_req_valid_i(req_valid),
    .ctrl_req_addr_i(req_addr),
    .ctrl_req_write_i(req_write),
    .ctrl_req_data_i(req_data),
    .ctrl_req_ack_o(req_ack),
    .ctrl_rsp_valid_o(rsp_valid),
    .ctrl_rsp_data_o(rsp_data),


    .sd_default_speed_clock_i(sd_clk_default),
    .sd_high_speed_clock_i(sd_clk_high),

    .sd_cmd_io(sd_cmd_pin),
    .sd_clk_o(sd_clock)
);

task wait_ctrl_ack();
    @(posedge ctrl_clk);
    while( !req_ack )
        @(posedge ctrl_clk);
endtask

initial begin
    #2000;

    // Send CMD0
    @(negedge ctrl_clk);
    req_valid = 1'b1;
    req_write = 1'b1;
    req_addr = 16'h0000;
    req_data = 32'h00000000;

    wait_ctrl_ack();

    @(negedge ctrl_clk);
    req_addr = 16'h0004;

    wait_ctrl_ack();

    @(negedge ctrl_clk);
    req_valid = 1'b0;

    #200;
    @(negedge ctrl_clk);
    req_valid = 1'b1;
    req_data = 17 | 256;

    wait_ctrl_ack();
    @(negedge ctrl_clk);
    req_valid = 1'b0;

    #200;
    @(negedge ctrl_clk);
    req_valid = 1'b1;
    req_addr = 16'h0000;
    req_data = 32'h000001a5;
    wait_ctrl_ack();

    @(negedge ctrl_clk);
    req_addr = 16'h0004;
    req_valid = 1'b1;
    req_data = 8 | 256;

    wait_ctrl_ack();
    @(negedge ctrl_clk);
    req_valid = 1'b0;

    #200;
    @(negedge ctrl_clk);
    req_valid = 1'b1;
    req_write = 1'b0;
    req_addr = 16'h0000;

    wait_ctrl_ack();
    @(negedge ctrl_clk);
    req_valid = 1'b0;

    @(posedge ctrl_clk);
    while( !rsp_valid )
        @(posedge ctrl_clk);

    @(negedge ctrl_clk);
    req_valid = 1'b1;
    req_write = 1'b0;
    req_addr = 16'h0010;

    wait_ctrl_ack();
    @(negedge ctrl_clk);
    req_valid = 1'b0;

    @(posedge ctrl_clk);
    while( !rsp_valid )
        @(posedge ctrl_clk);

    @(negedge ctrl_clk);
    req_valid = 1'b0;
end

enum { CMD_IDLE, CMD_RECV_HEADER, CMD_RECV_CRC, CMD_RECV_STOPBIT } cmd_state = CMD_IDLE;
logic [47:0] cmd;
int cmd_counter;
logic [6:0] cmd_crc_value;
crc#(
    .CRC_BITS(7),
    .INIT_VALUE(7'b0),
    .POLYNOM(7'b0001001)
) cmd_crc(
    .clock_i(sd_clock),
    .reset_i(cmd_state==CMD_IDLE),
    .bit_valid_i(cmd_state==CMD_RECV_HEADER),
    .bit_i(sd_cmd_signal),

    .crc_o(cmd_crc_value)
);

logic status = 1'b1;

logic verify = 1'b0, reply_active = 1'b0;
logic [5:0] verify__cmd;
logic [31:0] verify__args;

task verify_cmd();
    if( sd_cmd_signal != 1'b1 ) begin
        $display("CMD STOP bit is not 1");
        status = 1'bX;
    end

    if( cmd[45] != 1'b1 ) begin
        $display("CMD signal bit is not 1");
        status = 1'bX;
    end

    if( cmd[6:0] != cmd_crc_value ) begin
        $display("CMD bad CRC, got ", cmd[6:0], " calculated ", cmd_crc_value);
        status = 1'bX;
    end

    verify<=1'b1;
    verify__cmd<=cmd[44:39];
    verify__args<=cmd[38:7];
endtask

always_ff@(posedge sd_clock) begin
    verify <= 1'b0;

    if( cmd_state != CMD_IDLE ) begin
        cmd_counter <= cmd_counter - 1;
        cmd <= { cmd[46:0], sd_cmd_signal };
    end

    case(cmd_state)
        CMD_IDLE: begin
            if(sd_cmd_signal == 1'b0 && !reply_active) begin
                cmd_state <= CMD_RECV_HEADER;
                cmd_counter <= 38;
            end
        end
        CMD_RECV_HEADER: begin
            if( cmd_counter==0 ) begin
                cmd_state <= CMD_RECV_CRC;
                cmd_counter <= 6;
            end
        end
        CMD_RECV_CRC: begin
            if( cmd_counter==0 ) begin
                cmd_state <= CMD_RECV_STOPBIT;
            end
        end
        CMD_RECV_STOPBIT: begin
            cmd_state <= CMD_IDLE;

            verify_cmd();
        end
    endcase
end

int reply_count = 0;
logic [47:0] reply_buffer;

always_ff@(negedge sd_clock) begin
    if( reply_active ) begin
        if( reply_count!=0 ) begin
            reply_count <= reply_count-1;
            sd_cmd_drive <= reply_buffer[47];
            reply_buffer <= { reply_buffer[46:0], 1'bX };
        end else begin
            reply_count <= 0;
            sd_cmd_drive <= 1'bz;
            reply_active <= 1'b0;
        end
    end

    if( verify ) begin
        case(verify__cmd)
            6'd0: $display("Received CMD0");
            6'd17: begin
                reply_active <= 1'b1;
                $display("Received CMD17");
                reply_count <= 48;
                reply_buffer <= 48'b000100010000000000000000000010010000000001100111;
            end
        endcase
    end
end

endmodule
