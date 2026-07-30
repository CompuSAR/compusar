`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/10/2026 09:12:35 PM
// Design Name: 
// Module Name: sd_sim_top
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


module sd_sim_top(
    );

localparam MEM_WIDTH = 128;
localparam MEM_SIZE = 32768;
localparam DATA_BLOCK_BITS = 512;

logic sd_clk_default, sd_clk_high, ctrl_clk;

logic [MEM_WIDTH-1:0] memory[MEM_SIZE];

initial begin
    // 25MHz clock
    sd_clk_default = 1'b0;
    forever begin
        #20 sd_clk_default = 1'b1;
        #20 sd_clk_default = 1'b0;
    end
end

initial begin
    // 50MHz clock
    sd_clk_high = 1'b0;
    forever begin
        #10 sd_clk_high = 1'b1;
        #10 sd_clk_high = 1'b0;
    end
end

initial begin
    // ~75MHz clock
    ctrl_clk = 1'b0;
    forever begin
        #6.598 ctrl_clk = 1'b1;
        #6.598 ctrl_clk = 1'b0;
    end
end

logic req_valid = 1'b0, req_ack, req_write, rsp_valid;
logic [15:0] req_addr;
logic [31:0] req_data, rsp_data;

logic sd_cmd_drive = 1'bz;
wire sd_cmd_pin, sd_cmd_signal;
assign sd_cmd_pin = sd_cmd_drive;
assign sd_cmd_signal = sd_cmd_pin === 1'bZ ? 1'b1 : sd_cmd_pin;

logic [3:0] sd_data_drive = 4'bz;
wire [3:0] sd_data_pin, sd_data_signal;
assign sd_data_pin = sd_data_drive;
assign sd_data_signal[0] = sd_data_pin[0] === 1'bZ ? 1'b1 : sd_data_pin[0];
assign sd_data_signal[1] = sd_data_pin[1] === 1'bZ ? 1'b1 : sd_data_pin[1];
assign sd_data_signal[2] = sd_data_pin[2] === 1'bZ ? 1'b1 : sd_data_pin[2];
assign sd_data_signal[3] = sd_data_pin[3] === 1'bZ ? 1'b1 : sd_data_pin[3];

logic dma_req_valid, dma_req_write, dma_req_ack, dma_rsp_valid = 1'b0;
logic [31:0] dma_req_addr;
logic [MEM_WIDTH-1:0] dma_req_data, dma_rsp_data;

wire sd_clock;

sd sd(
    .ctrl_clock_i(ctrl_clk),

    .ctrl_req_valid_i(req_valid),
    .ctrl_req_addr_i(req_addr),
    .ctrl_req_write_i(req_write),
    .ctrl_req_data_i(req_data),
    .ctrl_req_ack_o(req_ack),
    .ctrl_rsp_valid_o(rsp_valid),
    .ctrl_rsp_data_o(rsp_data),

    .dma_req_valid_o(dma_req_valid),
    .dma_req_addr_o(dma_req_addr),
    .dma_req_write_o(dma_req_write),
    .dma_req_data_o(dma_req_data),
    .dma_req_ack_i(dma_req_ack),
    
    .dma_rsp_valid_i(dma_rsp_valid),
    .dma_rsp_data_i(dma_rsp_data),


    .sd_default_speed_clock_i(sd_clk_default),
    .sd_high_speed_clock_i(sd_clk_high),

    .sd_cmd_io(sd_cmd_pin),
    .sd_data_io(sd_data_pin),
    .sd_clk_o(sd_clock)
);

task wait_ctrl_ack();
    @(posedge ctrl_clk);
    while( !req_ack )
        @(posedge ctrl_clk);
endtask

task send_ctrl_cmd(input [15:0]addr, input [31:0]data);
    // Assume we're already at the negative edge of the clock
    req_valid = 1'b1;
    req_addr = addr;
    req_data = data;
    req_write = 1'b1;

    wait_ctrl_ack();

    @(negedge ctrl_clk);
    req_valid = 1'b0;
endtask

task read_ctrl_reg(input [15:0]addr);
    // Assume we're already at the negative edge of the clock
    req_valid = 1'b1;
    req_write = 1'b0;
    req_addr = addr;

    wait_ctrl_ack();

    @(negedge ctrl_clk);
    req_valid = 1'b0;

    @(posedge ctrl_clk);
    while( !rsp_valid )
        @(posedge ctrl_clk);
endtask

task get_cmd_status();
    do begin
        read_ctrl_reg(16'h0000);
    end while( rsp_data[31] );

    $displayh("CMD status ", rsp_data);
    @(negedge ctrl_clk);
    read_ctrl_reg(16'h001c);
    $displayh("  ", rsp_data);
    @(negedge ctrl_clk);
    read_ctrl_reg(16'h0018);
    $displayh("  ", rsp_data);
    @(negedge ctrl_clk);
    read_ctrl_reg(16'h0014);
    $displayh("  ", rsp_data);
    @(negedge ctrl_clk);
    read_ctrl_reg(16'h0010);
    $displayh("  ", rsp_data);
    @(negedge ctrl_clk);
endtask

localparam DMA_WRITE_ADDR = 32'h00000400;
initial begin
    #2000;

    // Send CMD0
    @(negedge ctrl_clk);
    send_ctrl_cmd(16'h0000, 32'h00000000);
    send_ctrl_cmd(16'h0004, 32'h00000000);
    get_cmd_status();

    #200;
    @(negedge ctrl_clk);
    send_ctrl_cmd(16'h0100, DMA_WRITE_ADDR);                              // DMA write address
    // Configure data reception: read direction (bit31=1), 1-bit mode (bit30=0), 512 bits
    send_ctrl_cmd(16'h0104, 32'h00000000 | DATA_BLOCK_BITS);
    send_ctrl_cmd(16'h0004, 17 | 32'h00001100);                         // CMD17, reply48, read data
    get_cmd_status();
    // Wait for data to finish coming
    do begin
        read_ctrl_reg(16'h0000);
    end while( rsp_data[30] );
    get_cmd_status();

    // Verify each chunk landed in memory in the correct order.
    // The SD controller receives bits MSB-first and writes them in arrival order,
    // so chunk 0 holds the most-significant DMA_WIDTH bits of data_block.
    for( int i=0; i < DATA_BLOCK_BITS / MEM_WIDTH; ++i ) begin
        automatic int addr = DMA_WRITE_ADDR/(MEM_WIDTH/8) + i;
        automatic logic [MEM_WIDTH-1:0] expected =
            data_block[DATA_BLOCK_BITS - 1 - i*MEM_WIDTH -: MEM_WIDTH];
        if( memory[addr] !== expected )
            $display("DMA MEMORY[%0d] MISMATCH: got %h, expected %h",
                     addr, memory[addr], expected);
        else
            $display("DMA MEMORY[%0d] OK: %h", addr, memory[addr]);
    end

    #200;
    @(negedge ctrl_clk);
    send_ctrl_cmd(16'h0000, 32'h000001a5);
    send_ctrl_cmd(16'h0004, 32'h00000108);
    get_cmd_status();

    @(negedge ctrl_clk);

    send_ctrl_cmd(16'h0000, 32'h00000000);
    send_ctrl_cmd(16'h0004, 32'h00000702);
    get_cmd_status();
end

enum { CMD_IDLE, CMD_RECV_HEADER, CMD_RECV_CRC, CMD_RECV_STOPBIT } cmd_state = CMD_IDLE;
logic [47:0] cmd;
int cmd_counter;
logic [6:0] cmd_crc_value, cmd_crc_init_value;
crc#(
    .CRC_BITS(7),
    .POLYNOM(7'b0001001)
) cmd_crc(
    .clock_i(sd_clock),
    .reset_i(cmd_state==CMD_IDLE),
    .bit_valid_i(cmd_state==CMD_RECV_HEADER),
    .bit_i(sd_cmd_signal),
    .init_value_i( 7'h00 ),

    .crc_o(cmd_crc_value)
);

logic status = 1'b1;

// ===== Data channel card simulation =====
logic [DATA_BLOCK_BITS-1:0] data_block =
    512'h0f0e0d0c0b0a090807060504030201001f1e1d1c1b1a191817161514131211102f2e2d2c2b2a292827262524232221207f7e7d7c7b7a79787776757473727170;

logic data_send_trigger = 1'b0;
enum { DC_IDLE, DC_SEND_START, DC_SEND_DATA, DC_SEND_CRC, DC_SEND_END } dc_state = DC_IDLE;
int dc_count = 0;
// Registered on negedge so the posedge CRC sees the state before this cycle's
// transition — ensures the last data bit is included and the CRC phase is not.
logic dc_crc_valid = 1'b0;

logic [15:0] data_card_crc_value;
crc#(
    .CRC_BITS(16),
    .POLYNOM(16'b0001000000100001)
) data_card_crc(
    .clock_i(sd_clock),
    .reset_i(dc_state == DC_IDLE),
    .bit_valid_i(dc_crc_valid),
    .bit_i(sd_data_drive[0]),
    .init_value_i(16'h0000),

    .crc_o(data_card_crc_value)
);

logic verify = 1'b0, reply_active = 1'b0;
logic [5:0] verify__cmd;
logic [31:0] verify__args;

task verify_cmd();
    if( sd_cmd_signal != 1'b1 ) begin
        $display("CMD STOP bit is not 1");
        status = 1'bX;
    end

    if( cmd[45] != 1'b1 ) begin
        $display("CMD signal bit is not 1");
        status = 1'bX;
    end

    if( cmd[6:0] != cmd_crc_value ) begin
        $display("CMD bad CRC, got ", cmd[6:0], " calculated ", cmd_crc_value);
        status = 1'bX;
    end

    verify<=1'b1;
    verify__cmd<=cmd[44:39];
    verify__args<=cmd[38:7];
endtask

always_ff@(posedge sd_clock) begin
    verify <= 1'b0;

    if( cmd_state != CMD_IDLE ) begin
        cmd_counter <= cmd_counter - 1;
        cmd <= { cmd[46:0], sd_cmd_signal };
    end

    case(cmd_state)
        CMD_IDLE: begin
            if(sd_cmd_signal == 1'b0 && !reply_active) begin
                cmd_state <= CMD_RECV_HEADER;
                cmd_counter <= 38;
            end
        end
        CMD_RECV_HEADER: begin
            if( cmd_counter==0 ) begin
                cmd_state <= CMD_RECV_CRC;
                cmd_counter <= 6;
            end
        end
        CMD_RECV_CRC: begin
            if( cmd_counter==0 ) begin
                cmd_state <= CMD_RECV_STOPBIT;
            end
        end
        CMD_RECV_STOPBIT: begin
            cmd_state <= CMD_IDLE;

            verify_cmd();
        end
    endcase
end

int reply_count = 0;
logic [135:0] reply_buffer;

always_ff@(negedge sd_clock) begin
    if( reply_active ) begin
        if( reply_count!=0 ) begin
            reply_count <= reply_count-1;
            sd_cmd_drive <= reply_buffer[reply_count-1];
        end else begin
            reply_count <= 0;
            sd_cmd_drive <= 1'bz;
            reply_active <= 1'b0;
            reply_buffer <= 'X;
        end
    end

    if( verify ) begin
        case(verify__cmd)
            6'd0: $display("Received CMD0");
            6'd02: begin
                reply_active <= 1'b1;
                $display("Received CMD02");
                reply_count <= 136;
                reply_buffer <= 136'h3f7f0000000000000000000000000071a7;
            end
            6'd17: begin
                reply_active <= 1'b1;
                $display("Received CMD17");
                reply_count <= 48;
                reply_buffer <= 48'b000100010000000000000000000010010000000001100111;
                data_send_trigger <= 1'b1;
            end
        endcase
    end
end

// Data channel card state machine: drives sd_data_pin[0] in 1-bit mode
always_ff@(negedge sd_clock) begin
    dc_crc_valid <= (dc_state == DC_SEND_DATA);

    case(dc_state)
        DC_IDLE: begin
            sd_data_drive <= 4'bz;
            if( data_send_trigger && !reply_active ) begin
                data_send_trigger <= 1'b0;
                dc_state <= DC_SEND_START;
                dc_count <= DATA_BLOCK_BITS - 1;
                $display("Data: starting block send (%0d bits)", DATA_BLOCK_BITS);
            end
        end
        DC_SEND_START: begin
            sd_data_drive[0] <= 1'b0; // start bit
            dc_state <= DC_SEND_DATA;
        end
        DC_SEND_DATA: begin
            sd_data_drive[0] <= data_block[dc_count];
            if( dc_count == 0 ) begin
                dc_state <= DC_SEND_CRC;
                dc_count <= 15;
            end else begin
                dc_count <= dc_count - 1;
            end
        end
        DC_SEND_CRC: begin
            if( dc_count == 15 ) begin
                // All data bits have been clocked into both CRC modules — validate now
                if( sd.data_crc_value[0] !== data_card_crc_value )
                    $display("DATA CRC MISMATCH: DUT computed %h, testbench expected %h",
                             sd.data_crc_value[0], data_card_crc_value);
                else
                    $display("DATA CRC OK: %h", data_card_crc_value);
            end
            sd_data_drive[0] <= data_card_crc_value[dc_count];
            if( dc_count == 0 )
                dc_state <= DC_SEND_END;
            else
                dc_count <= dc_count - 1;
        end
        DC_SEND_END: begin
            sd_data_drive[0] <= 1'b1; // end bit
            dc_state <= DC_IDLE;
            $display("Data: block send complete");
        end
    endcase
end

// DMA handler
int dma_write_count = 0;

always_ff@(posedge ctrl_clk) begin
    dma_rsp_valid <= 1'b0;

    if( dma_req_valid )
        dma_req_ack <= 1'b1;

    if( dma_req_valid && dma_req_ack ) begin
        automatic logic [31:0]mem_addr = dma_req_addr[31:$clog2(MEM_WIDTH/8)];

        if( dma_req_write ) begin
            memory[mem_addr] <= dma_req_data;
            dma_write_count <= dma_write_count + 1;
        end else begin
            dma_rsp_data <= memory[mem_addr];
            dma_rsp_valid <= 1'b1;
        end

        dma_req_ack <= 1'b0;
    end
end

endmodule
