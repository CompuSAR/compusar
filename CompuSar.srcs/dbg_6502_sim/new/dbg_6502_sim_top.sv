`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/19/2026 04:22:47 PM
// Design Name: 
// Module Name: dbg_6502_sim_top
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


module dbg_6502_sim_top();

logic clock = 1'b0;

initial forever begin
    #50 clock = 1'b1;
    #50 clock = 1'b0;
end

logic cpu_req_valid = 1'b0, cpu_req_ack, cpu_req_write;
logic[15:0] cpu_req_addr;
logic[7:0] cpu_req_write_data;

logic sync = 1'b0, memlock = 1'b0, vp = 1'b0;

sync_bus#(.DATA_WIDTH(32), .ADDR_WIDTH(16)) riscv_bus();
logic intr, n_halt;

assign cpu_req_ack = n_halt;

initial riscv_bus.req_valid = 1'b0;

dbg6502 mut(
    .clk_i(clock),

    .cpu_req_valid_i(cpu_req_valid),
    .cpu_req_ack_i(cpu_req_ack),
    .cpu_req_write_i(cpu_req_write),
    .cpu_req_addr_i(cpu_req_addr),
    .cpu_req_write_data_i(cpu_req_write_data),

    .cpu_sync_i(sync),
    .cpu_memlock_i(memlock),
    .cpu_vector_pull_i(vp),

    .ctrl(riscv_bus),
    .ctrl_intr_o(intr),

    .n_halt_o(n_halt)
);

task write_reg(input [15:0] addr, input [31:0] data);
    @(negedge clock);
    riscv_bus.req_valid = 1'b1;
    riscv_bus.req_write = 1'b1;
    riscv_bus.req_addr = addr;
    riscv_bus.req_data = data;

    @(posedge clock);
    while( !riscv_bus.req_ack )
        @(posedge clock);

    @(negedge clock);
    riscv_bus.req_valid = 1'b0;
endtask

task read_reg(input [15:0] addr, output [31:0] result);
    @(negedge clock);
    riscv_bus.req_valid = 1'b1;
    riscv_bus.req_write = 1'b0;
    riscv_bus.req_addr = addr;

    @(posedge clock);
    while( !riscv_bus.req_ack )
        @(posedge clock);

    @(negedge clock);
    riscv_bus.req_valid = 1'b0;

    @(posedge clock);
    while( !riscv_bus.rsp_valid )
        @(posedge clock);

    result = riscv_bus.rsp_data;
endtask

initial begin
    logic[31:0] state;

    write_reg(16'h8000, { 4'b0001, 4'b0001, 8'h00, 16'hfe5e });

    forever begin
        @(posedge clock)
        while( !intr )
            @(posedge clock);

        read_reg(16'h0004, state);
        $display("DBG: %08x", state);

        write_reg(16'h0000, 32'b101);
    end
end

task c6502_read(input [15:0] address, input setsync);
    cpu_req_valid = 1'b1;
    cpu_req_write = 1'b0;
    cpu_req_addr = address;
    sync = setsync;

    @(posedge clock);
    while( !cpu_req_ack )
        @(posedge clock);

    @(negedge clock);
    cpu_req_valid = 1'b0;
endtask

task c6502_write(input [15:0] address, input [7:0] data);
    cpu_req_valid = 1'b1;
    cpu_req_write = 1'b1;
    cpu_req_addr = address;
    cpu_req_write_data = data;

    @(posedge clock);
    while( !cpu_req_ack )
        @(posedge clock);

    @(negedge clock);
    cpu_req_valid = 1'b0;
endtask

initial begin
    #10000;

    @(negedge clock);
    c6502_read(16'hfffc, 1'b0);
    c6502_read(16'hfffd, 1'b0);
    c6502_read(16'hfe5e, 1'b1);
    c6502_read(16'hfe5f, 1'b0);
    c6502_write(16'hfe5e, 8'h42);
    c6502_read(16'hfe60, 1'b1);
    c6502_read(16'hfe61, 1'b0);
    c6502_read(16'hfe62, 1'b0);
    c6502_read(16'hfe63, 1'b1);
    c6502_read(16'hfe64, 1'b0);
end

endmodule
