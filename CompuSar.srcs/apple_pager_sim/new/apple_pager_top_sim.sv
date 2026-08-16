`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/16/2026 08:16:08 PM
// Design Name: 
// Module Name: apple_pager_top_sim
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


module apple_pager_top_sim();

logic clock = 1'b0;

initial forever begin
    #500 clock = 1'b1;
    #500 clock = 1'b0;
end

logic req_valid = 1'b0, req_write = 1'b0;
logic[15:0] req_addr;
logic[31:0] mem_addr;

sync_bus#(.DATA_WIDTH(32), .ADDR_WIDTH(32)) ctrl();

apple_pager pager(
    .clock_i(clock),

    .cpu_req_valid_i(req_valid),
    .cpu_req_write_i(req_write),
    .cpu_req_addr_i(req_addr),

    .mem_req_addr_o(mem_addr),

    .ctrl(ctrl)
);

task ctrl_write(logic[15:0] addr, logic[31:0] data);
    @(negedge clock);
    ctrl.req_valid = 1'b1;
    ctrl.req_write = 1'b1;
    ctrl.req_addr = addr;
    ctrl.req_data = data;

    @(posedge clock);
    while( !ctrl.req_ack ) begin
        @(posedge clock);
    end
    
    @(negedge clock);
    ctrl.req_valid = 1'b0;
endtask

task cpu_op(logic[15:0] addr, logic write, logic[31:0] expected);
    req_valid = 1'b1;
    req_write = write;
    req_addr = addr;

    @(posedge clock);
    if( expected != mem_addr ) begin
        $error("[%0t] FAILURE: Address %04x %s: expected %08x actual %08x", $time(), addr, write ? "W" : "R", expected, mem_addr);
    end

    @(negedge clock);
    req_valid = 1'b0;
endtask

task cpu_read(logic[15:0] addr, logic[31:0] expected);
    cpu_op(addr, 1'b0, expected);
endtask

task cpu_write(logic[15:0] addr, logic[31:0] expected);
    cpu_op(addr, 1'b1, expected);
endtask

initial begin
    // Main memory
    ctrl_write( 16'h0000, 32'h1000_0000 );
    ctrl_write( 16'h0800, 32'h1000_0000 );

    // IO bank
    ctrl_write( 16'h0004, 32'h2000_c000 );
    ctrl_write( 16'h0804, 32'h0000_0000 );

    // Low ROM bank
    ctrl_write( 16'h0008, 32'h3000_0000 );
    ctrl_write( 16'h0808, 32'h3000_0000 );

    // High ROM bank
    ctrl_write( 16'h000c, 32'h4000_0000 );
    ctrl_write( 16'h080c, 32'h0000_0000 );

    // Devnull address
    ctrl_write( 16'h0010, 32'h0000_0014 );
    ctrl_write( 16'h0810, 32'h0000_0028 );

    // Slots
    ctrl_write( 16'h0100, 32'h0000_0000 );
    ctrl_write( 16'h0110, 32'hc100_c100 );
    ctrl_write( 16'h0120, 32'hc200_c200 );
    ctrl_write( 16'h0130, 32'hc300_c300 );
    ctrl_write( 16'h0140, 32'hc400_c400 );
    ctrl_write( 16'h0150, 32'hc500_c500 );
    ctrl_write( 16'h0160, 32'hc600_c600 );
    ctrl_write( 16'h0170, 32'hc700_c700 );

    cpu_read(16'h0000, 32'h1000_0000);
    cpu_write(16'hb681, 32'h1000_b681);

    cpu_read(16'hd012, 32'h3000_d012);
    cpu_write(16'hd012, 32'h3000_d012);

    cpu_read(16'hef03, 32'h4000_ef03);
    cpu_write(16'hef03, 32'h0000_0028);

    cpu_read(16'hc0ec, 32'h2000_00ec);
    cpu_write(16'hc0ec, 32'h0000_0028);

    cpu_read(16'hc101, 32'hc100_0001);
    cpu_write(16'hc101, 32'h0000_0028);

    cpu_read(16'hc202, 32'hc200_0002);
    cpu_write(16'hc202, 32'h0000_0028);

    cpu_read(16'hc303, 32'hc300_0003);
    cpu_write(16'hc303, 32'h0000_0028);

    cpu_read(16'hc404, 32'hc400_0004);
    cpu_write(16'hc404, 32'h0000_0028);

    cpu_read(16'hc505, 32'hc500_0005);
    cpu_write(16'hc505, 32'h0000_0028);

    cpu_read(16'hc606, 32'hc600_0006);
    cpu_write(16'hc606, 32'h0000_0028);

    cpu_read(16'hc707, 32'hc700_0007);
    cpu_write(16'hc707, 32'h0000_0028);

    cpu_read(16'hc808, 32'h0000_0014);
    cpu_write(16'hc808, 32'h0000_0028);

    $display("All tests finished successfully");
    $finish(1);
end

endmodule
