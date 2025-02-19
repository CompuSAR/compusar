`timescale 1ns / 1ps

module display# (
    CLOCK_SPEED = 50000000,
    NORTH_BUS_WIDTH = 128,
    TEXT_PAGE_ADDR = 32'h400,
    BAUD_RATE = 115200
)(
    input clock_i,
    input reset_i,

    output logic req_valid_o,
    output logic [31:0] req_addr_o,
    input req_ack_i,

    input rsp_valid_i,
    input [NORTH_BUS_WIDTH-1:0] rsp_data_i,

    output uart_send_o
);

localparam REFRESH_RATE = 10;
localparam REFRESH_DIVIDER = CLOCK_SPEED / REFRESH_RATE;

logic [$clog2(REFRESH_DIVIDER)-1 : 0]refresh_divider = 0;
enum { IDLE, FETCHING, WAITING, SENDING } state = IDLE;
logic [NORTH_BUS_WIDTH-1:0] prefetch_buffer;
logic [$clog2(NORTH_BUS_WIDTH)-1:0] prefetch_buffer_fill = 0;

logic [15:0] offset;

logic uart_send_valid, uart_send_ack;

task handle_fetching();
    if( req_ack_i )
        state <= WAITING;
endtask

always_comb begin
    req_valid_o = 1'b0;
    req_addr_o = 32'hX;

    if( state==FETCHING ) begin
        req_valid_o = 1'b1;
        req_addr_o = TEXT_PAGE_ADDR + offset;
    end

    uart_send_valid = prefetch_buffer_fill!=0;
end

task handle_waiting();
    if( rsp_valid_i ) begin
        state <= SENDING;
        prefetch_buffer <= rsp_data_i;
        prefetch_buffer_fill <= NORTH_BUS_WIDTH/8;
        offset <= offset + NORTH_BUS_WIDTH/8;
    end
endtask

task handle_sending();
    if( prefetch_buffer_fill == 0 ) begin
        if( offset >= 16'h400 )
            state <= IDLE;
        else
            state <= FETCHING;
    end
endtask

always_ff@(posedge clock_i) begin
    refresh_divider <= refresh_divider-1;

    if( reset_i ) begin
        refresh_divider <= 0;
        prefetch_buffer_fill <= 0;
        state <= IDLE;
    end else begin
        if( uart_send_valid && uart_send_ack ) begin
            // Shift up the buffer
            prefetch_buffer <= { prefetch_buffer[NORTH_BUS_WIDTH-9:0], 8'h00 };
            prefetch_buffer_fill <= prefetch_buffer_fill - 1;
        end

        case( state )
            IDLE: if( refresh_divider==0 ) begin
                state <= FETCHING;
                refresh_divider <= REFRESH_DIVIDER;
                offset <= 0;
            end
            FETCHING: handle_fetching();
            WAITING: handle_waiting();
            SENDING:  handle_sending();
        endcase
    end
end

function logic[7:0] byte2char(input [7:0] by);
    if(! by[5])
        byte2char = { 3'b010, by[4:0] };
    else
        byte2char = { 3'b001, by[4:0] };
endfunction

uart_send#(.ClockDivider(CLOCK_SPEED / BAUD_RATE)) uart(
    .clock(clock_i),
    .data_in(byte2char( prefetch_buffer[NORTH_BUS_WIDTH-1:NORTH_BUS_WIDTH-8] )),
    .data_in_ready(uart_send_valid),
    .receive_ready(uart_send_ack),
    .out_bit(uart_send_o)
);

endmodule
