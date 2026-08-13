`timescale 1ns / 1ps

module apple_io

import a2_io::*;

(
    input clock_i,

    sync_bus.SLAVE cpu_bus,

    output logic perph_req_valid_o[NumPeripherals] = '{ default: 1'b0 },
    input perph_req_ack_i[NumPeripherals],
    output [15:0] perph_req_addr_o[NumPeripherals],
    output perph_req_write_o[NumPeripherals],
    output [7:0] perph_req_write_data_o[NumPeripherals],

    input perph_rsp_valid_i[NumPeripherals],
    input [7:0] perph_rsp_read_data_i[NumPeripherals],

    sync_bus.SLAVE ctrl,

    output ctrl_intr_o
    );

logic io_op_pending = 1'b0;
logic io_op_parsed = 1'b0;
Peripheral io_active_periph;

logic forwarded = 1'b0;
logic forwarded_rsp_valid = 1'b0;
logic [7:0] forwarded_rsp_read_data;

assign cpu_bus.req_ack = ! io_op_pending;
assign cpu_bus.rsp_valid =
    forwarded ?
    forwarded_rsp_valid :
    ( io_op_parsed && perph_rsp_valid_i[io_active_periph] );
assign cpu_bus.rsp_data =
    forwarded ?
    forwarded_rsp_read_data :
    perph_rsp_read_data_i[io_active_periph];

assign ctrl_intr_o = forwarded;

logic [15:0] pending_req_addr;
logic pending_req_write;
logic [7:0] pending_req_write_data;

task perph_req(input Peripheral perph);
    io_active_periph <= perph;
    perph_req_valid_o[perph] <= 1'b1;
endtask

always_ff@(posedge clock_i) begin
    // Handle control requests
    ctrl.rsp_valid <= 1'b0;

    if( forwarded && forwarded_rsp_valid )
        forwarded <= 1'b0;

    if( ctrl.req_valid && ctrl.req_ack ) begin
        if( ctrl.req_write ) begin
            // Write requests
            case( ctrl.req_addr )
                16'h0000: begin
                    if( pending_req_write ) begin
                        forwarded <= 1'b0;
                    end else begin
                        forwarded_rsp_valid <= 1'b1;
                    end
                    forwarded_rsp_read_data <= ctrl.req_data[7:0];
                end
            endcase
        end else begin
            // Read requests
            case( ctrl.req_addr )
                16'h0000: ctrl.rsp_data <=
                    { forwarded, pending_req_write, 6'h0, pending_req_write_data, pending_req_addr };
                default: ctrl.rsp_data <= 32'hX;
            endcase

            ctrl.rsp_valid <= 1'b1;
        end
    end

    // Handle payload requests
    if( cpu_bus.req_valid && cpu_bus.req_ack ) begin
        pending_req_addr <= cpu_bus.req_addr;
        pending_req_write <= cpu_bus.req_write;
        pending_req_write_data <= cpu_bus.req_data;

        io_op_pending <= 1'b1;
        io_op_parsed <= 1'b0;
    end

    if( io_op_pending && !io_op_parsed ) begin
        if( pending_req_write ) begin
            casex( pending_req_addr )
                16'hc0xx: begin
                    forwarded <= 1'b1;
                end
                default: begin
                    perph_req(Mem);
                end
            endcase
        end else begin
            casex( pending_req_addr )
                16'hc010: forwarded <= 1'b1;
                16'hc0xx: perph_req(Mem);
                default: perph_req(Mem);
            endcase
        end

        io_op_parsed <= 1'b1;
    end

    if( io_op_pending && io_op_parsed ) begin
        if( perph_req_valid_o[io_active_periph] ) begin
            // We're trying to issue a request
            if( perph_req_ack_i[io_active_periph] ) begin
                perph_req_valid_o[io_active_periph] <= 1'b0;

                if( pending_req_write ) begin
                    // Write operations are done as soon as they are acknowledged.
                    io_op_pending <= 1'b0;
                end
            end
        end else begin
            // Request was already acknowledged (read)
            if( perph_rsp_valid_i[io_active_periph] ) begin
                // Response received
                io_op_pending <= 1'b0;
            end
        end
    end
end

genvar i;

generate

for( i=0; i<NumPeripherals; ++i ) begin
    assign perph_req_addr_o[i] = pending_req_addr;
    assign perph_req_write_o[i] = pending_req_write;
    assign perph_req_write_data_o[i] = pending_req_write_data;
end

endgenerate

endmodule
