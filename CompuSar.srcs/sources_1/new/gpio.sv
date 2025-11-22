`timescale 1ns / 1ps

module gpio#(NUM_IN_PORTS = 1, NUM_OUT_PORTS = 1)
(
    input               clock_i,

    // Request
    input [15:0]        req_addr_i,
    input [31:0]        req_data_i,
    input               req_write_i,
    input               req_valid_i,
    output logic        req_ready_o,

    // Response
    output logic[31:0]  rsp_data_o,
    output logic        rsp_valid_o,

    // IO
    input [31:0]        gp_in[NUM_IN_PORTS-1:0],
    output [31:0]       gp_out[NUM_OUT_PORTS-1:0]
);

logic [31:0] rsp_data_next;
assign req_ready_o = 1'b1;

logic [31:0] gp_out_value[NUM_OUT_PORTS] = '{ {NUM_OUT_PORTS{ 32'hffffffff }} };
assign gp_out = gp_out_value;

logic [31:0] gp_in_latch[NUM_IN_PORTS];

always_ff@(posedge clock_i) begin
    rsp_data_o <= rsp_data_next;
    rsp_valid_o <= !req_write_i && req_valid_i;

    if( req_valid_i && req_write_i )
        gp_out_value[req_addr_i] <= req_data_i;
end

always_ff@(posedge clock_i) begin
    gp_in_latch <= gp_in;
end

always_comb begin
    if( req_valid_i )
        rsp_data_next = gp_in_latch[req_addr_i];
    else
        rsp_data_next = 32'bX;
end

endmodule
