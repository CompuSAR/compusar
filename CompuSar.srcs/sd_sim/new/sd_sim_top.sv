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

task send_ctrl_cmd(input [15:0]addr, input [31:0]data);
    // Assume we're already at the negative edge of the clock
    req_valid = 1'b1;
    req_addr = addr;
    req_data = data;
    req_write = 1'b1;

    wait_ctrl_ack();

    @(negedge ctrl_clk);
    req_valid = 1'b0;
endtask

task read_ctrl_reg(input [15:0]addr);
    // Assume we're already at the negative edge of the clock
    req_valid = 1'b1;
    req_write = 1'b0;
    req_addr = addr;

    wait_ctrl_ack();

    @(negedge ctrl_clk);
    req_valid = 1'b0;

    @(posedge ctrl_clk);
    while( !rsp_valid )
        @(posedge ctrl_clk);
endtask

task get_cmd_status();
    do begin
        read_ctrl_reg(16'h0000);
    end while( rsp_data[31] );

    $displayh("CMD status ", rsp_data);
    @(negedge ctrl_clk);
    read_ctrl_reg(16'h001c);
    $displayh("  ", rsp_data);
    @(negedge ctrl_clk);
    read_ctrl_reg(16'h0018);
    $displayh("  ", rsp_data);
    @(negedge ctrl_clk);
    read_ctrl_reg(16'h0014);
    $displayh("  ", rsp_data);
    @(negedge ctrl_clk);
    read_ctrl_reg(16'h0010);
    $displayh("  ", rsp_data);
    @(negedge ctrl_clk);
endtask

initial begin
    #2000;

    // Send CMD0
    @(negedge ctrl_clk);
    send_ctrl_cmd(16'h0000, 32'h00000000);
    send_ctrl_cmd(16'h0004, 32'h00000000);
    get_cmd_status();

    #200;
    @(negedge ctrl_clk);
    send_ctrl_cmd(16'h0004, 17 | 256);
    get_cmd_status();

    #200;
    @(negedge ctrl_clk);
    send_ctrl_cmd(16'h0000, 32'h000001a5);
    send_ctrl_cmd(16'h0004, 32'h00000108);
    get_cmd_status();

    @(negedge ctrl_clk);

    send_ctrl_cmd(16'h0000, 32'h00000000);
    send_ctrl_cmd(16'h0004, 32'h00000702);
    get_cmd_status();
end

enum { CMD_IDLE, CMD_RECV_HEADER, CMD_RECV_CRC, CMD_RECV_STOPBIT } cmd_state = CMD_IDLE;
logic [47:0] cmd;
int cmd_counter;
logic [6:0] cmd_crc_value, cmd_crc_init_value;
crc#(
    .CRC_BITS(7),
    .POLYNOM(7'b0001001)
) cmd_crc(
    .clock_i(sd_clock),
    .reset_i(cmd_state==CMD_IDLE),
    .bit_valid_i(cmd_state==CMD_RECV_HEADER),
    .bit_i(sd_cmd_signal),
    .init_value_i( 7'h00 ),

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
logic [135:0] reply_buffer;

always_ff@(negedge sd_clock) begin
    if( reply_active ) begin
        if( reply_count!=0 ) begin
            reply_count <= reply_count-1;
            sd_cmd_drive <= reply_buffer[reply_count-1];
        end else begin
            reply_count <= 0;
            sd_cmd_drive <= 1'bz;
            reply_active <= 1'b0;
            reply_buffer <= 'X;
        end
    end

    if( verify ) begin
        case(verify__cmd)
            6'd0: $display("Received CMD0");
            6'd02: begin
                reply_active <= 1'b1;
                $display("Received CMD02");
                reply_count <= 136;
                reply_buffer <= 136'h3f7f0000000000000000000000000071a7;
            end
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
