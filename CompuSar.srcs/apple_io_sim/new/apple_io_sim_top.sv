`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/23/2026 12:16:19 PM
// Design Name: 
// Module Name: apple_io_sim_top
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


module apple_io_sim_top();

import a2_io::*;

logic clock = 1'b0;

initial forever begin
    #50 clock = 1'b1;
    #50 clock = 1'b0;
end

sync_bus#(.DATA_WIDTH(32), .ADDR_WIDTH(16)) ctrl_bus();
sync_bus#(.DATA_WIDTH(8), .ADDR_WIDTH(16)) cpu_bus();

logic interrupt;

logic perph_req_valid[NumPeripherals];
logic perph_req_ack[NumPeripherals];
logic [15:0]perph_req_addr[NumPeripherals];
logic perph_req_write[NumPeripherals];
logic [7:0]perph_req_data[NumPeripherals];

logic perph_rsp_valid[NumPeripherals];
logic [7:0]perph_rsp_data[NumPeripherals];

apple_io mut(
    .clock_i(clock),

    .cpu_bus(cpu_bus),

    .perph_req_valid_o(perph_req_valid),
    .perph_req_ack_i(perph_req_ack),
    .perph_req_addr_o(perph_req_addr),
    .perph_req_write_o(perph_req_write),
    .perph_req_write_data_o(perph_req_data),

    .perph_rsp_valid_i(perph_rsp_valid),
    .perph_rsp_read_data_i(perph_rsp_data),

    .ctrl(ctrl_bus),

    .ctrl_intr_o(interrupt)
);

task ctrl_write_reg(input [15:0] addr, input [31:0] data);
    ctrl_bus.req_valid = 1'b1;
    ctrl_bus.req_addr = addr;
    ctrl_bus.req_data = data;
    ctrl_bus.req_write = 1'b1;

    @(posedge clock);
    while( !ctrl_bus.req_ack )
        @(posedge clock);

    @(negedge clock);
    ctrl_bus.req_valid = 1'b0;
endtask

task ctrl_read_reg(input [15:0] addr, output [31:0] data);
    ctrl_bus.req_valid = 1'b1;
    ctrl_bus.req_addr = addr;
    ctrl_bus.req_data = 'X;
    ctrl_bus.req_write = 1'b0;

    @(posedge clock);
    while( !ctrl_bus.req_ack )
        @(posedge clock);

    @(negedge clock);
    ctrl_bus.req_valid = 1'b0;
    @(posedge clock);
    while( !ctrl_bus.rsp_valid )
        @(posedge clock);

    data = ctrl_bus.rsp_data;

    @(negedge clock);
endtask

logic [31:0] regvalue;

initial begin
    // Ctrl CPU thread
    ctrl_bus.req_valid = 1'b0;

    forever begin
        @(posedge clock);
        while( !interrupt )
            @(posedge clock);

        #1000;
        @(negedge clock);
        ctrl_read_reg(0, regvalue);

        ctrl_write_reg(0, 0);
    end
end

initial begin
    cpu_bus.req_valid = 1'b0;
end

int busptr = 0;
struct {
    logic w;
    logic [15:0] a;
    logic [7:0] d;
} busops[] = '{
    { 1, 16'h0000, 8'h17 },
    { 1, 16'hc000, 8'h42 },
    { 0, 16'hc004, 8'hXX },
    { 0, 16'hc0e4, 8'hXX },
    { 0, 16'hc0ec, 8'hXX }
};
enum { REQ, ACK, RSP } state = REQ;

always_ff@(posedge clock) begin
    // CPU 6502 thread

    if( busptr < $size(busops) ) begin
        case( state )
            REQ: begin
                cpu_bus.req_valid <= 1'b1;
                cpu_bus.req_addr <= busops[busptr].a;
                cpu_bus.req_write <= busops[busptr].w;
                cpu_bus.req_data <= busops[busptr].d;
                state <= ACK;
            end
            ACK: begin
                if( cpu_bus.req_ack ) begin
                    cpu_bus.req_valid <= 1'b0;
                    state <= cpu_bus.req_write ? REQ : RSP;
                    busptr <= busptr + 1;
                end
            end
            RSP: begin
                if( cpu_bus.rsp_valid )
                    state <= REQ;
            end
        endcase
    end
end

genvar i;

generate

for( i=0; i<NumPeripherals; ++i ) begin
    initial begin
        // Peripherals thread
        perph_req_ack[i] = 1'b1;
        perph_rsp_valid[i] = 1'b0;
    end

    int answer = 42;
    always_ff@(posedge clock) begin
        perph_rsp_valid[i] <= 1'b0;

        if( perph_req_valid[i] && perph_req_ack[i] ) begin
            if( !perph_req_write[i] ) begin
                perph_rsp_valid[i] <= 1'b1;
                perph_rsp_data[i] <= answer;
                answer <= answer + 1;
            end
        end
    end
end

endgenerate

endmodule
