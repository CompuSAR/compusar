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
localparam NUM_ROWS = 24, NUM_COLOUMNS = 40;

localparam string ClearScreenSequence = "\x1b[H\x1b[2J\x1b[3J\x1b[?25l";
localparam string NewLineSequence = "\x0d\x0a";


logic [$clog2(REFRESH_DIVIDER)-1 : 0]refresh_divider = 0;
enum { IDLE, FETCHING, WAITING, SENDING, CLEARSCREEN, NEWLINE } state = IDLE;
logic [NORTH_BUS_WIDTH-1:0] prefetch_buffer;
logic [$clog2(NORTH_BUS_WIDTH)-1:0] prefetch_buffer_fill = 0, prefetch_buffer_fill_next;

logic [4:0] esc_seq_counter = 0;
logic [15:0] offset;
logic [15:0] col_num = 0;
logic [7:0] line_num = 0;               // Always runs from 0 to 23 (even for high res)
wire middle_third = line_num[3];        // Indicate we're on lines 8-15

logic uart_send_valid, uart_send_ack;
logic [7:0] uart_send_data;

task handle_fetching();
    if( req_ack_i )
        state <= WAITING;
endtask

always_comb begin
    if( prefetch_buffer_fill!=0 && uart_send_ack )
        prefetch_buffer_fill_next = prefetch_buffer_fill - 1;
    else
        prefetch_buffer_fill_next = prefetch_buffer_fill;
end

always_comb begin
    req_valid_o = 1'b0;
    req_addr_o = 32'hX;
    uart_send_data = 8'hXX;

    if( state==FETCHING ) begin
        req_valid_o = 1'b1;
        req_addr_o = TEXT_PAGE_ADDR + offset;

        uart_send_valid = prefetch_buffer_fill!=0;
        uart_send_data = byte2char( prefetch_buffer[7:0] );
    end else if( state==CLEARSCREEN ) begin
        uart_send_valid = 1'b1;
        uart_send_data = ClearScreenSequence[esc_seq_counter];
    end else if( state==NEWLINE ) begin
        uart_send_valid = 1'b1;
        uart_send_data = NewLineSequence[esc_seq_counter];
    end else begin
        uart_send_valid = prefetch_buffer_fill!=0;
        uart_send_data = byte2char( prefetch_buffer[7:0] );
    end
end

task handle_clear_screen();
    if( uart_send_ack ) begin
        if( esc_seq_counter==ClearScreenSequence.len()-1 ) begin
            esc_seq_counter <= 0;
            state <= FETCHING;
        end else begin
            esc_seq_counter <= esc_seq_counter+1;
        end
    end
endtask

task handle_waiting();
    if( rsp_valid_i ) begin
        state <= SENDING;
        if( !middle_third ) begin
            prefetch_buffer <= rsp_data_i;
            prefetch_buffer_fill <= NORTH_BUS_WIDTH/8;
        end else begin
            prefetch_buffer <= { {NORTH_BUS_WIDTH/2{1'bX}}, rsp_data_i[NORTH_BUS_WIDTH-1:NORTH_BUS_WIDTH/2] };
            prefetch_buffer_fill <= NORTH_BUS_WIDTH/16;
        end
    end
endtask

wire [31:0] off_third, off_line, off_adj, next_line;

assign next_line = line_num + 1;
assign off_third = next_line[4:3] * NUM_COLOUMNS;
assign off_line = next_line[2:0] * 128;
assign off_adj = next_line[3] ? NORTH_BUS_WIDTH/16 : 0;

task handle_sending();
    if( uart_send_ack ) begin
        if( col_num == NUM_COLOUMNS-1 ) begin
            col_num <= 0;

            if( line_num == NUM_ROWS-1 ) begin
                state <= IDLE;
                line_num <= 0;
            end else begin
                state <= NEWLINE;
                line_num <= line_num+1;
                offset <= off_third + off_line - off_adj;
            end
        end else begin
            col_num <= col_num+1;

            if( prefetch_buffer_fill_next == 0 ) begin
                state <= FETCHING;
                offset <= offset + NORTH_BUS_WIDTH/8;
            end
        end
    end
endtask

task handle_new_line();
    if( uart_send_ack ) begin
        if( esc_seq_counter==NewLineSequence.len()-1 ) begin
            esc_seq_counter <= 0;
            state <= FETCHING;
        end else begin
            esc_seq_counter <= esc_seq_counter+1;
        end
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
            // Shift down the buffer
            prefetch_buffer <= { 8'h00, prefetch_buffer[NORTH_BUS_WIDTH-1:8] };
            prefetch_buffer_fill <= prefetch_buffer_fill_next;
        end

        case( state )
            IDLE: if( refresh_divider==0 ) begin
                state <= CLEARSCREEN;
                refresh_divider <= REFRESH_DIVIDER;
                offset <= 0;
                col_num <= 0;
            end
            CLEARSCREEN: handle_clear_screen();
            FETCHING: handle_fetching();
            WAITING: handle_waiting();
            SENDING:  handle_sending();
            NEWLINE: handle_new_line();
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
    .data_in(uart_send_data),
    .data_in_ready(uart_send_valid),
    .receive_ready(uart_send_ack),
    .out_bit(uart_send_o)
);

endmodule
