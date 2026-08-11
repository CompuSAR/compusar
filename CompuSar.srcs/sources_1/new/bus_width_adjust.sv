`timescale 1ns / 1ps

module bus_width_adjust(
    input                                               clock_i,

    sync_bus_write_mask.SLAVE                           north_port,
    sync_bus_write_mask.MASTER                          south_port
);

localparam IN_WIDTH = $bits(north_port.req_data);
localparam OUT_WIDTH = $bits(south_port.req_data);
localparam ADDR_WIDTH = $bits(north_port.req_addr);

initial
    if( $bits(south_port.req_addr) != ADDR_WIDTH ) begin
        $error("Inputs to bus_width_adjust must have matching address widths");
    end

initial
    if( IN_WIDTH >= OUT_WIDTH ) begin
        $error("South port must be wider than north port inbus_width_adjust");
    end

// Straight passthrough
assign south_port.req_valid = north_port.req_valid;
assign south_port.req_addr = north_port.req_addr;

assign north_port.req_ack = south_port.req_ack;
assign north_port.rsp_valid = south_port.rsp_valid;

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
    if( north_port.req_valid )
        cmd_segment_next = north_port.req_addr[SEGMENT_SELECTOR_HIGH-1:SEGMENT_SELECTOR_LOW];
    else
        cmd_segment_next = cmd_segment;
end

genvar i;
generate
    for( i=0; i<EXPANSION_FACTOR; ++i ) begin
        assign south_port.req_data[(i+1)*IN_WIDTH-1:i*IN_WIDTH] = north_port.req_data;
        assign south_port.req_write_mask[(i+1)*(IN_WIDTH/8)-1:i*(IN_WIDTH/8)] =
            cmd_segment_next%EXPANSION_FACTOR == i ? north_port.req_write_mask : { (IN_WIDTH/8){1'b0} };
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
assign consolidator[EXPANSION_FACTOR_LOG-1].expanded = south_port.rsp_data;
assign north_port.rsp_data = consolidator[0].consolidated;

always_ff@(posedge clock_i) begin
    if( north_port.req_valid && south_port.req_ack )
        cmd_segment <= cmd_segment_next;
end


endmodule
