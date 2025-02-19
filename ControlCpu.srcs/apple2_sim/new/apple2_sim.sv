`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/17/2025 04:10:56 PM
// Design Name: 
// Module Name: apple2_sim
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


module apple2_sim();

localparam BUS8_FREQ_DIV = 5;

logic clock, ctrl_cpu_clock;

assign ctrl_cpu_clock = clock;

logic reset, sync;

initial begin
    clock = 1'b0;
    forever begin
        #6.667 clock = 1'b1;
        #6.666 clock = 1'b0;
    end
end

logic [7:0] memory[1024*1024];
initial
    $readmemh("Apple2_Plus.mem", memory, 20'hfd000);

logic mem_req_valid, mem_req_ack = 1'b1, mem_req_write, mem_rsp_valid;
logic [31:0] mem_req_addr;
logic [7:0] mem_req_data, mem_rsp_data;

wire bus8_req_valid, bus8_req_ack, bus8_rsp_valid;
wire bus8_req_write;
wire [7:0] bus8_req_data, bus8_rsp_data;
wire [15:0] bus8_req_addr;
wire [31:0] bus8_paged_req_addr;

logic apple_pager_enable, apple_pager_req_ack, apple_pager_req_write, apple_pager_rsp_valid;
logic [15:0] apple_pager_req_addr;
logic [31:0] apple_pager_req_data, apple_pager_rsp_data;

initial begin
    reset = 1'b1;

    apple_pager_enable = 1'b1;
    apple_pager_req_write = 1'b1;
    apple_pager_req_addr = 16'h0000;
    apple_pager_req_data = 32'h00000000;
    @(posedge clock);
    @(negedge clock);

    apple_pager_req_addr = 16'h0003;
    @(posedge clock);
    @(negedge clock);

    apple_pager_req_addr = 16'h0001;
    apple_pager_req_data = 32'h000f0000;
    @(posedge clock);
    @(negedge clock);

    apple_pager_req_addr = 16'h0002;
    @(posedge clock);
    @(negedge clock);

    apple_pager_req_addr = 16'h0004;
    @(posedge clock);
    @(negedge clock);

    apple_pager_req_addr = 16'h0005;
    @(posedge clock);
    @(negedge clock);

    apple_pager_enable = 1'b0;

    #50 reset = 1'b0;
end

always_ff@(posedge clock) begin
    mem_rsp_valid <= 1'b0;
    mem_rsp_data <= 8'hXX;

    if( mem_req_valid ) begin
        if( mem_req_write )
            memory[mem_req_addr] <= mem_req_data;
        else begin
            mem_rsp_data <= memory[mem_req_addr];
            mem_rsp_valid <= 1'b1;
        end
    end
end

freq_div_bus#() freq_div_6502(
    .clock_i( ctrl_cpu_clock ),
    .ctl_div_nom_i( BUS8_FREQ_DIV ),
    .ctl_div_denom_i( 16'd1 ),
    .reset_i( reset ),

    .slow_cmd_valid_i( bus8_req_valid ),
    .slow_cmd_ready_o( bus8_req_ack ),

    .fast_cmd_valid_o(mem_req_valid),
    .fast_cmd_ready_i(mem_req_ack)
    );

sar6502_sync apple_cpu(
    .clock_i( ctrl_cpu_clock ),

    .reset_i( reset ),
    .nmi_i( 1'b0 ),
    .irq_i( 1'b0 ),
    .set_overflow_i( 1'b0 ),

    .sync_o( sync ),

    .bus_req_valid_o( bus8_req_valid ),
    .bus_req_address_o( bus8_req_addr ),
    .bus_req_write_o( bus8_req_write ),
    .bus_req_ack_i( bus8_req_ack ),
    .bus_req_data_o( bus8_req_data ),
    .bus_rsp_valid_i( bus8_rsp_valid ),
    .bus_rsp_data_i( bus8_rsp_data )
);

apple_pager pager(
    .clock_i(clock),

    .cpu_req_valid_i(bus8_req_valid),
    .cpu_req_write_i(bus8_req_write),
    .cpu_req_addr_i(bus8_req_addr),

    .mem_req_addr_o(bus8_paged_req_addr),

    .ctrl_req_valid_i(apple_pager_enable),
    .ctrl_req_write_i(apple_pager_req_write),
    .ctrl_req_addr_i(apple_pager_req_addr),
    .ctrl_req_data_i(apple_pager_req_data),
    .ctrl_req_ack_o(apple_pager_req_ack),
    .ctrl_rsp_valid_o(apple_pager_rsp_valid),
    .ctrl_rsp_data_o(apple_pager_rsp_data)
);

//assign mem_req_valid = bus8_req_valid;
assign mem_req_addr = bus8_paged_req_addr;
assign mem_req_write = bus8_req_write;
assign mem_req_data = bus8_req_data;
assign bus8_rsp_valid = mem_rsp_valid;
assign bus8_rsp_data = mem_rsp_data;

/*
bus_width_adjust#(.IN_WIDTH(8), .OUT_WIDTH(CACHELINE_BITS), .ADDR_WIDTH(32)) bus8_width_adjuster(
    .clock_i( clock ),
    .in_cmd_valid_i( bus8_req_valid ),
    .in_cmd_addr_i( bus8_paged_req_addr ),
    .in_cmd_write_mask_i( 1'b1 ),
    .in_cmd_write_data_i( bus8_req_data ),
    .in_rsp_read_data_o( bus8_rsp_data ),

    .out_cmd_ready_i( bus8_req_ack ),
    .out_cmd_write_mask_o( cache_port_cmd_write_mask_s[CACHE_PORT_IDX_6502] ),
    .out_cmd_write_data_o( cache_port_cmd_write_data_s[CACHE_PORT_IDX_6502] ),
    .out_rsp_valid_i( cache_port_rsp_valid_n[CACHE_PORT_IDX_6502] ),
    .out_rsp_read_data_i( cache_port_rsp_read_data_n[CACHE_PORT_IDX_6502] )
);
*/

endmodule
