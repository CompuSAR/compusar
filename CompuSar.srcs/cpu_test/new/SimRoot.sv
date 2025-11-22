`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/09/2022 02:52:33 PM
// Design Name: 
// Module Name: SimRoot
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


module SimRoot(

    );

logic clock;
logic reset, timer, irq, softirq;

logic [31:0]data_in, instruction_in;
logic data_ready, inst_ready, data_error;

logic [31:0]memory[65536];

VexRiscv cpu(
    .clk(clock), .reset(reset), .timerInterrupt(timer), .externalInterrupt(irq), .softwareInterrupt(softirq),
    .iBus_cmd_ready(1), .iBus_rsp_payload_inst(instruction_in), .iBus_rsp_valid(inst_ready), .iBus_rsp_payload_error(0),
    .dBus_rsp_ready(data_ready), .dBus_rsp_error(data_error), .dBus_rsp_data(data_in), .dBus_cmd_ready(1)
);

initial begin
    clock = 1;
    forever begin
        #500 clock = 0;
        #500 clock = 1;
    end
end

initial $readmemh("test_program.mem", memory);

initial begin
    reset = 1;
    timer = 0;
    irq = 0;
    softirq = 0;

    #1500 reset = 0;
end

logic [31:0]mem_val;

always_ff@(posedge clock) begin
    mem_val = memory[ cpu.iBus_cmd_payload_pc[15:2] ];
    instruction_in <= mem_val;

    if( cpu.iBus_cmd_valid ) begin
        inst_ready <= 1;
        //instruction_in <= { mem_val[7:0], mem_val[15:8], mem_val[23:16], mem_val[31:24] };
    end else begin
        inst_ready <= 0;
        //instruction_in <= 32'hX;
    end
end

/*
logic[31:0] inst_value;
always_comb begin
    inst_ready = 1;
    //instruction_in = memory[ inst_addr[15:2] ];
    inst_value = memory[ inst_addr[15:2] ];
    instruction_in = { inst_value[7:0], inst_value[15:8], inst_value[23:16], inst_value[31:24] };
end
*/

always_ff@(posedge clock) begin
    if( cpu.dBus_cmd_payload_wr && cpu.dBus_cmd_valid )
        memory[ cpu.dBus_cmd_payload_address[15:2] ] <= cpu.dBus_cmd_payload_data;

    data_error <= 0;
    data_in <= memory[ cpu.dBus_cmd_payload_address[15:2] ];
    data_ready <= cpu.dBus_cmd_valid;
end

endmodule
