`timescale 1ns / 1ps

module bus_width_adjust#(
    IN_WIDTH = 32,
    OUT_WIDTH = 32,
    ADDR_WIDTH = 32
)(
    input                                               clock_i,

    input                                               in_cmd_valid_i,
    input [ADDR_WIDTH-1:0]                              in_cmd_addr_i,
    input [IN_WIDTH/8-1:0]                              in_cmd_write_mask_i,
    input [IN_WIDTH-1:0]                                in_cmd_write_data_i,
    output [IN_WIDTH-1:0]                               in_rsp_read_data_o,

    input                                               out_cmd_ready_i,
    output [OUT_WIDTH/8-1:0]                            out_cmd_write_mask_o,
    output [OUT_WIDTH-1:0]                              out_cmd_write_data_o,
    input                                               out_rsp_valid_i,
    input [OUT_WIDTH-1:0]                               out_rsp_read_data_i
);

initial begin
    if( IN_WIDTH>OUT_WIDTH )
        $error("Tried to initialize a narrowing bus width adjuster");

    if( (OUT_WIDTH/IN_WIDTH)*IN_WIDTH != OUT_WIDTH )
        $error("OUT_WIDTH must be a multiple of IN_WIDTH");
end

localparam EXPANSION_FACTOR = OUT_WIDTH / IN_WIDTH;
localparam EXPANSION_FACTOR_LOG = $clog2(EXPANSION_FACTOR);
localparam SEGMENT_SELECTOR_LOW = $clog2(IN_WIDTH/8);
localparam SEGMENT_SELECTOR_HIGH = $clog2(OUT_WIDTH/8);

logic [EXPANSION_FACTOR_LOG-1:0] cmd_segment, cmd_segment_next;

always_comb begin
    if( in_cmd_valid_i )
        cmd_segment_next = in_cmd_addr_i[SEGMENT_SELECTOR_HIGH-1:SEGMENT_SELECTOR_LOW];
    else
        cmd_segment_next = cmd_segment;
end

genvar i;
generate
    for( i=0; i<EXPANSION_FACTOR; ++i ) begin
        assign out_cmd_write_data_o[(i+1)*IN_WIDTH-1:i*IN_WIDTH] = in_cmd_write_data_i;
        assign out_cmd_write_mask_o[(i+1)*(IN_WIDTH/8)-1:i*(IN_WIDTH/8)] =
            cmd_segment_next%EXPANSION_FACTOR == i ? in_cmd_write_mask_i : { (IN_WIDTH/8){1'b0} };
    end

    // Select portion of reply that interests us
    for( i=0; i<EXPANSION_FACTOR_LOG; i=i+1 ) begin : consolidator
        wire [IN_WIDTH*(1<<(i+1))-1:0] expanded;
        wire [IN_WIDTH*(1<<i)-1:0] consolidated;

        assign consolidated = cmd_segment[i] ? expanded[$bits(expanded)-1:IN_WIDTH*(1<<i)] : expanded;
    end : consolidator

    for( i=0; i<EXPANSION_FACTOR_LOG-1; i=i+1 ) begin
        assign consolidator[i].expanded = consolidator[i+1].consolidated;
    end
endgenerate

// Set the boundary conditions
assign consolidator[EXPANSION_FACTOR_LOG-1].expanded = out_rsp_read_data_i;
assign in_rsp_read_data_o = consolidator[0].consolidated;

always_ff@(posedge clock_i) begin
    cmd_segment <= cmd_segment_next;
end


endmodule
