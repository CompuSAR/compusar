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
    req_data = 17;

    wait_ctrl_ack();
    @(negedge ctrl_clk);
    req_valid = 1'b0;
end

endmodule
