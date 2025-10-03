`timescale 1ns / 1ps

module uart_ctrl#(
    parameter ClockDivider = 50,
    parameter SimMode = 0,
    parameter InputDelay = 4
)
(
    input clock,

    input [15:0] req_addr_i,
    input req_valid_i,
    input req_write_i,
    input [31:0] req_data_i,
    output logic req_ack_o,

    output logic rsp_valid_o,
    output logic[31:0] rsp_data_o,

    output logic intr_send_ready_o,
    output logic intr_recv_ready_o = 1'b0,

    output uart_tx,
    input uart_rx
);

localparam REG_UART_DATA        = 16'h0000;
localparam REG_UART_STATUS      = 16'h0004;

logic [7:0] uart_send_data, uart_recv_data, uart_recv_data_latched = 8'h00;
logic uart_send_data_ready = 1'b0, uart_recv_data_ready;
logic receive_ready;

logic [InputDelay-1:0]input_buffer = {InputDelay{1'b1}};

always_ff@(posedge clock) begin
    input_buffer[0] <= uart_rx;

    if( InputDelay>1 )
        input_buffer[InputDelay-1:1] <= input_buffer[InputDelay-2:0];
end

always_comb begin
    if( !SimMode ) begin
        req_ack_o = intr_send_ready_o || req_addr_i!=16'h0;
        intr_send_ready_o = receive_ready;
    end else begin
        req_ack_o = 1'b1;
        intr_send_ready_o = 1'b1;
    end
end

uart_send#(.ClockDivider(ClockDivider))
uart_send(
    .clock(clock),
    .data_in(uart_send_data),
    .data_in_ready(uart_send_data_ready),
    
    .out_bit(uart_tx),
    .receive_ready(receive_ready)
);

uart_recv#(.ClockDivider(ClockDivider))
uart_recv(
    .clock(clock),
    .input_bit(input_buffer[InputDelay-1]),

    .data_out(uart_recv_data),
    .data_ready(uart_recv_data_ready),

    .break_received(),
    .error()
);

always_ff@(posedge clock) begin
    uart_send_data_ready <= 1'b0;
    rsp_valid_o <= 1'b0;
    rsp_data_o <= 32'hXXXXXXXX;

    if( req_ack_o && req_valid_i ) begin
        // We have a control request
        if( req_write_i ) begin
            // Write
            case( req_addr_i )
                REG_UART_DATA: begin
                    uart_send_data_ready <= 1'b1;
                    uart_send_data <= req_data_i;
                end
            endcase
        end else begin
            rsp_valid_o <= 1'b1;
            // Read
            case( req_addr_i )
                REG_UART_DATA: begin
                    rsp_data_o <= {~intr_recv_ready_o, 23'h0, uart_recv_data_latched};
                    intr_recv_ready_o <= 1'b0;
                end
                REG_UART_STATUS: rsp_data_o <= { {30{1'b0}}, intr_recv_ready_o, intr_send_ready_o };
                default: rsp_data_o <= 32'hXXXXXXXX;
            endcase
        end
    end

    if( uart_recv_data_ready ) begin
        uart_recv_data_latched <= uart_recv_data;
        intr_recv_ready_o <= 1'b1;
    end
end

endmodule
