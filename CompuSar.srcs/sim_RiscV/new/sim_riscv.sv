`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/19/2025 05:39:36 PM
// Design Name: 
// Module Name: sim_riscv
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


module sim_riscv();

logic clock = 1'b0;
logic reset = 1'b1;

logic [31:0] memory[65535:0];

initial begin
    #5000 reset = 1'b0;
end

initial begin
    $readmemh("testprog.mem", memory);

    forever begin
        #500 clock = ~clock;
    end
end

logic [31:0] iBus_cmd_addr, iBus_rsp_data, dBus_cmd_addr, dBus_cmd_data, dBus_rsp_data;
logic iBus_cmd_valid, iBus_rsp_valid, iBus_rsp_error, dBus_cmd_valid, dBus_rsp_error, dBus_rsp_valid, dBus_cmd_wr;
logic [3:0] dBus_cmd_wr_mask;

VexRiscv cpu(
    .clk(clock), .reset(reset), .softwareInterrupt(1'b0), .timerInterrupt(1'b0), .externalInterrupt(1'b0),
    .iBus_cmd_valid(iBus_cmd_valid), .iBus_cmd_ready(1'b1), .iBus_cmd_payload_pc(iBus_cmd_addr),
    .iBus_rsp_valid(iBus_rsp_valid), .iBus_rsp_payload_error(iBus_rsp_error), .iBus_rsp_payload_inst(iBus_rsp_data),
    .dBus_cmd_valid(dBus_cmd_valid), .dBus_cmd_payload_address(dBus_cmd_addr), .dBus_cmd_ready(1'b1), .dBus_cmd_payload_data(dBus_cmd_data), .dBus_cmd_payload_mask(dBus_cmd_wr_mask), .dBus_cmd_payload_wr(dBus_cmd_wr),
    .dBus_rsp_data(dBus_rsp_data), .dBus_rsp_error(dBus_rsp_error), .dBus_rsp_ready(dBus_rsp_valid)
);

always_ff@(posedge clock) begin
    iBus_rsp_valid <= 1'b0;
    iBus_rsp_error <= 1'b0;
    iBus_rsp_data <= 32'hX;

    if( iBus_cmd_valid ) begin
        if( (iBus_cmd_addr & 32'h8003fffc) == (iBus_cmd_addr | 32'h80000000) ) begin
            iBus_rsp_valid <= 1'b1;
            iBus_rsp_data <= memory[iBus_cmd_addr[17:2]];
        end else begin
            iBus_rsp_error <= 1'b1;
            iBus_rsp_valid <= 1'b1;
        end
    end

    dBus_rsp_valid <= 1'b0;
    dBus_rsp_error <= 1'b0;
    dBus_rsp_data <= 32'h12345678;

    if( dBus_cmd_valid ) begin
        if( (dBus_cmd_addr & 32'h8003fffc) == (dBus_cmd_addr | 32'h80000000) ) begin
            if( dBus_cmd_wr ) begin
                memory[dBus_cmd_addr[17:2]] <= (memory[dBus_cmd_addr[17:2]] & ~dBus_cmd_wr_mask) | (dBus_cmd_data & dBus_cmd_wr_mask);
            end else begin
                dBus_rsp_valid <= 1'b1;
                dBus_rsp_data <= memory[dBus_cmd_addr[17:2]];
            end
        end else begin
            dBus_rsp_error <= 1'b1;
            dBus_rsp_valid <= 1'b1;
        end
    end
end

endmodule
