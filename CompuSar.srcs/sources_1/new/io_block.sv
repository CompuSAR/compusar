`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/27/2022 04:45:40 PM
// Design Name: 
// Module Name: io_block
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


module io_block#(
    parameter NUM_PORTS = 2,
    parameter FIRST_AUX_PORT = 1
)(
    input clock,

    sync_bus_write_mask.SLAVE cpu_port,
    output logic rsp_error,

    sync_bus_write_mask.MASTER ddr_port,

    sync_bus.MASTER ports[NUM_PORTS]
);

localparam DATA_WIDTH = $bits(cpu_port.req_data);

initial begin
    if( DATA_WIDTH != $bits(ddr_port.req_data) || DATA_WIDTH != $bits(ports[0].req_data) ) begin
        $error("Bus width for io_block must be equal on all ports");
    end
end

logic write;
assign write = cpu_port.req_write_mask != 0;

logic request_pending = 1'b0;
logic [$clog2(NUM_PORTS+2)-1:0] pending_port, pending_port_next;

// We can't directly iterate the interfaces because... Vivado. So we "copy"
// them to local variables
logic ports_req_valid[NUM_PORTS];
logic ports_req_ack[NUM_PORTS];
logic ports_rsp_valid[NUM_PORTS];
logic [DATA_WIDTH-1:0] ports_rsp_data[NUM_PORTS];

always_comb begin
    // The ports that get forwarded with no logic
    ddr_port.req_addr = cpu_port.req_addr;
    ddr_port.req_data = cpu_port.req_data;
    ddr_port.req_write_mask = cpu_port.req_write_mask;
end

always_ff@(posedge clock) begin
    if( request_pending && cpu_port.rsp_valid ) begin
        request_pending <= 1'b0;
    end

    if( cpu_port.req_valid && cpu_port.req_ack ) begin
        request_pending <= !write;
        pending_port <= pending_port_next;
    end
end

task default_state_current();
    int i;

    pending_port_next = pending_port;

    cpu_port.req_ack = 1'b1;

    ddr_port.req_valid = 1'b0;

    for( i=0; i<NUM_PORTS; i++ ) begin
        ports_req_valid[i] = 1'b0;
    end
endtask

function logic is_ddr(logic [31:0]address);
    is_ddr = address[31:30] == 2'b10;
endfunction

function logic is_io(logic [31:0]address);
    is_io = address[31:30] == 2'b11;
endfunction

function logic[7:0] calc_port_addr(int port);
    if( port<FIRST_AUX_PORT )
        calc_port_addr = port;
    else
        calc_port_addr = port + 8'h80 - FIRST_AUX_PORT;
endfunction

always_comb begin
    // Previous cycle analysis
    cpu_port.rsp_valid = 1'bX;
    rsp_error = 1'b0;
    cpu_port.rsp_data = 32'bX;

    if( request_pending ) begin
        if( pending_port==NUM_PORTS+1 ) begin
            cpu_port.rsp_valid = 1'b1;
            rsp_error = 1'b1;
        end else if( pending_port==NUM_PORTS ) begin
            cpu_port.rsp_valid = ddr_port.rsp_valid;
            cpu_port.rsp_data = ddr_port.rsp_data;
        end else begin
            cpu_port.rsp_valid = ports_rsp_valid[pending_port];
            cpu_port.rsp_data = ports_rsp_data[pending_port];
        end
    end
end

always_comb begin
    int i;
    automatic logic handled = 1'b0;

    default_state_current();

    // Current cycle analysis
    if( request_pending && !cpu_port.rsp_valid ) begin
        // Can't accept this command
        cpu_port.req_ack = 1'b0;
    end else if( cpu_port.req_valid ) begin
        if( is_ddr(cpu_port.req_addr) ) begin
            ddr_port.req_valid = cpu_port.req_valid;
            cpu_port.req_ack = ddr_port.req_ack;

            pending_port_next = NUM_PORTS;
            handled = 1'b1;
        end else if(cpu_port.req_valid) begin
            for( i=0; i<NUM_PORTS; ++i ) begin
                if( cpu_port.req_addr[23:16] == calc_port_addr(i) ) begin
                    ports_req_valid[i] = 1'b1;
                    cpu_port.req_ack = ports_req_ack[i];

                    handled = 1'b1;
                    pending_port_next = i;
                end
            end
        end

        if( !handled ) begin
            cpu_port.req_ack = 1'b1;
            pending_port_next = NUM_PORTS+1;    // Indicate error
        end
    end
end

genvar i;

generate

for( i=0; i<NUM_PORTS; i++ ) begin
    assign ports[i].req_valid = ports_req_valid[i];
    assign ports[i].req_write = write;
    assign ports[i].req_addr = cpu_port.req_addr;
    assign ports[i].req_data = cpu_port.req_data;
    assign ports_req_ack[i] = ports[i].req_ack;
    assign ports_rsp_valid[i] = ports[i].rsp_valid;
    assign ports_rsp_data[i] = ports[i].rsp_data;
end

endgenerate

endmodule
