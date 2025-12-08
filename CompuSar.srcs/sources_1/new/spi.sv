`timescale 1ns / 1ps

module spi_ctrl#(
    parameter MEM_DATA_WIDTH = 32
)
(
    // Control interface
    input                       cpu_clock_i,
    input                       spi_ref_clock_i,
    output                      irq,

    output logic[3:0]           debug,

    input                       ctrl_cmd_valid_i,
    input [15:0]                ctrl_cmd_address_i,
    input [31:0]                ctrl_cmd_data_i,
    input                       ctrl_cmd_write_i,
    output                      ctrl_cmd_ack_o,

    output logic                ctrl_rsp_valid_o,
    output logic[31:0]          ctrl_rsp_data_o,

    // SPI interface
    output logic                spi_cs_n_o,
    inout [3:0]                 spi_dq_io,
    output                      spi_clk_o,

    // DMA interface
    output logic                dma_cmd_valid_o,
    output logic[31:0]          dma_cmd_address_o,
    output [MEM_DATA_WIDTH-1:0] dma_cmd_data_o,
    output logic                dma_cmd_write_o,
    input                       dma_cmd_ack_i,

    input                       dma_rsp_valid_i,
    input [MEM_DATA_WIDTH-1:0]  dma_rsp_data_i
);

localparam MEM_DATA_WIDTH_BYTES = MEM_DATA_WIDTH/8;

/*********************************************************************************
* CPU clock logic
*********************************************************************************/

// SPI commands scan the bytes LSB but the bits in the byte MSB, so we need to
// shuffle the bits around a bit.
logic [MEM_DATA_WIDTH-1:0] dma_cmd_data_mixed, dma_rsp_data_mixed;

reg [31:0] cpu_dma_addr_send, cpu_dma_addr_recv, cpu_num_send_cycles, cpu_num_recv_cycles, cpu_transfer_mode;
reg [31:0] spi_num_send_cycles, spi_num_recv_cycles, spi_transfer_mode;
reg cpu_transaction_active = 1'b0;

wire cpu_qspi_state = cpu_transfer_mode[16];

xpm_cdc_array_single#(
    .WIDTH(32),
    .SIM_ASSERT_CHK(1)
) cdc_num_send_cycles(
    .src_clk(cpu_clock_i),
    .src_in(cpu_num_send_cycles),

    .dest_clk(spi_ref_clock_i),
    .dest_out(spi_num_send_cycles)
), cdc_num_recv_cycles(
    .src_clk(cpu_clock_i),
    .src_in(cpu_num_recv_cycles),

    .dest_clk(spi_ref_clock_i),
    .dest_out(spi_num_recv_cycles)
), cdc_transfer_mode(
    .src_clk(cpu_clock_i),
    .src_in(cpu_transfer_mode),

    .dest_clk(spi_ref_clock_i),
    .dest_out(spi_transfer_mode)
);

logic [MEM_DATA_WIDTH-1:0]      cpu_dma_read_data, spi_dma_read_data;
logic                           cpu_dma_read_valid = 1'b0, spi_dma_read_valid;
logic                           cpu_dma_read_ack, spi_dma_read_ack = 1'b0;

logic [MEM_DATA_WIDTH-1:0]      cpu_dma_write_data;
logic                           cpu_dma_write_valid, spi_dma_write_valid = 1'b0;
logic                           cpu_dma_write_ack = 1'b0, spi_dma_write_ack;

logic [31:0]                    cpu_send_counter = 0, cpu_recv_counter = 0;

wire cpu_send_idle = !cpu_dma_read_valid && !cpu_dma_read_ack;

task cpu_set_invalid_state();
endtask

wire[31:0] cpu_num_send_bits = cpu_qspi_state ? cpu_num_send_cycles * 4 : cpu_num_send_cycles;
wire[31:0] cpu_num_recv_bits = cpu_qspi_state ? cpu_num_recv_cycles * 4 : cpu_num_recv_cycles;
logic[31:0] cpu_rounded_send_bits, cpu_rounded_recv_bits;
assign cpu_rounded_send_bits = cpu_num_send_bits + (MEM_DATA_WIDTH - 1);
assign cpu_rounded_recv_bits = cpu_num_recv_bits + (MEM_DATA_WIDTH - 1);

task start_transaction();
    cpu_transaction_active <= 1'b1;

    cpu_send_counter <= cpu_rounded_send_bits[31:$clog2(MEM_DATA_WIDTH)];
    cpu_recv_counter <= cpu_rounded_recv_bits[31:$clog2(MEM_DATA_WIDTH)];
endtask

task wait_transaction();
    ctrl_rsp_data_o <= 32'b0;
endtask

assign ctrl_cmd_ack_o = !cpu_transaction_active;

logic cpu_dma_read_in_progress = 1'b0, cpu_dma_read_in_progress_next;
logic [MEM_DATA_WIDTH-1:0] cpu_data_buffer;
logic cpu_data_buffer_full = 1'b0;

assign cpu_dma_read_data = cpu_data_buffer;

always_ff@(posedge cpu_clock_i) begin
    ctrl_rsp_valid_o <= 1'b0;

    if( ctrl_cmd_valid_i && ctrl_cmd_ack_o ) begin
        if( ctrl_cmd_write_i ) begin
            // Write
            case( ctrl_cmd_address_i )
                16'h0000: start_transaction();
                16'h0004: cpu_dma_addr_send <= ctrl_cmd_data_i;
                16'h0008: cpu_num_send_cycles <= ctrl_cmd_data_i;
                16'h000c: cpu_dma_addr_recv <= ctrl_cmd_data_i;
                16'h0010: cpu_num_recv_cycles <= ctrl_cmd_data_i;
                16'h0014: cpu_transfer_mode <= ctrl_cmd_data_i;
                default: cpu_set_invalid_state();
            endcase
        end else begin
            // Read
            ctrl_rsp_valid_o <= 1'b1;
            case( ctrl_cmd_address_i )
                16'h0000: wait_transaction();
                16'h0004: ctrl_rsp_data_o <= cpu_dma_addr_send;
                16'h0008: ctrl_rsp_data_o <= cpu_num_send_cycles;
                16'h000c: ctrl_rsp_data_o <= cpu_dma_addr_recv;
                16'h0010: ctrl_rsp_data_o <= cpu_num_recv_cycles;
                16'h0014: ctrl_rsp_data_o <= cpu_transfer_mode;
            endcase
        end
    end

    if( cpu_dma_read_valid && cpu_dma_read_ack )
        cpu_dma_read_valid <= 1'b0;

    if( cpu_dma_write_ack && !cpu_dma_write_valid )
        cpu_dma_write_ack <= 1'b0;

    cpu_dma_read_in_progress <= cpu_dma_read_in_progress_next;

    if( cpu_dma_read_in_progress && dma_rsp_valid_i ) begin
        // DMA read in progress
        cpu_data_buffer <= dma_rsp_data_mixed;
        cpu_data_buffer_full <= 1'b1;
        cpu_send_counter <= cpu_send_counter-1;
        cpu_dma_addr_send <= cpu_dma_addr_send + MEM_DATA_WIDTH_BYTES;
        cpu_dma_read_in_progress <= 1'b0;
    end

    if( dma_cmd_valid_o && dma_cmd_write_o && dma_cmd_ack_i ) begin
        // DMA write sent
        cpu_dma_addr_recv <= cpu_dma_addr_recv + MEM_DATA_WIDTH_BYTES;
    end

    if( cpu_data_buffer_full && cpu_send_idle )
        cpu_dma_read_valid <= 1'b1;

    if( cpu_data_buffer_full && cpu_dma_read_valid && cpu_dma_read_ack )
        cpu_data_buffer_full <= 1'b0;

    if( dma_cmd_valid_o && dma_cmd_write_o && dma_cmd_ack_i ) begin
        cpu_dma_write_ack <= 1'b1;
        cpu_dma_addr_send <= cpu_dma_addr_send + MEM_DATA_WIDTH_BYTES;
        cpu_recv_counter <= cpu_recv_counter - 1;
    end

    if( cpu_transaction_active && cpu_send_counter==0 && cpu_recv_counter==0 )
        cpu_transaction_active <= 1'b0;
end

always_comb begin
    cpu_dma_read_in_progress_next = cpu_dma_read_in_progress;
    dma_cmd_valid_o = 1'b0;
    dma_cmd_data_mixed = { MEM_DATA_WIDTH{1'bX} };
    dma_cmd_write_o = 1'bX;
    dma_cmd_address_o = 32'bX;

    if( cpu_transaction_active ) begin
        if( cpu_send_counter>0 ) begin
            // DMA read
            if( !cpu_data_buffer_full ) begin
                if( cpu_send_idle && !cpu_dma_read_in_progress ) begin
                    dma_cmd_valid_o = 1'b1;
                    dma_cmd_address_o = cpu_dma_addr_send;
                    dma_cmd_write_o = 1'b0;

                    if( dma_cmd_ack_i )
                        cpu_dma_read_in_progress_next = 1'b1;
                end
            end
        end else begin
            // DMA write
            if( cpu_dma_write_valid && !cpu_dma_write_ack ) begin
                dma_cmd_valid_o = 1'b1;
                dma_cmd_write_o = 1'b1;
                dma_cmd_data_mixed = cpu_dma_write_data;
                dma_cmd_address_o = cpu_dma_addr_recv;
            end
        end
    end
end

genvar i, j;
generate

// Remix bits: Pure LSB to mixed LSByte-MSbit
for( i=0; i<MEM_DATA_WIDTH_BYTES; i+=1 ) begin
    for( j=0; j<8; j++ ) begin
        // Send data shifts down and needs the bits in each byte reversed
        assign dma_rsp_data_mixed[i*8+7-j] = dma_rsp_data_i[i*8+j];
        // Recv data shifts up, and needs the byte order reversed
        assign dma_cmd_data_o[i*8+j] = dma_cmd_data_mixed[(MEM_DATA_WIDTH_BYTES-i-1)*8+j];
    end
end

endgenerate

/*********************************************************************************
* SPI clock logic
*********************************************************************************/

/*
* Bit 0: SPI chip select (active low)
* Bit 1: SPI clock enable
* Bit 2: Send
* Bit 3: Recv
* Bit 4: Shifter load
*/
enum logic[4:0] {
    IDLE =              5'b00001,
    SEND_STARTING =     5'b10000,
    SEND_ACTIVE =       5'b00110,
    SEND_PENDING =      5'b10100,
    DUMMY =             5'b00010,
    RECV_ACTIVE =       5'b01010,
    RECV_PENDING =      5'b01000,
    IDLE_PENDING =      5'b01001
} spi_state = IDLE, spi_state_next;

logic [31:0] spi_send_cycles = 0, spi_recv_cycles = 0;
logic [16:0] spi_dummy_cycles = 0;
logic spi_quad_mode = 1'b0;
logic [MEM_DATA_WIDTH-1:0] spi_shift_buffer;
localparam MEM_DATA_WIDTH_CLOG = $clog2(MEM_DATA_WIDTH);
logic [MEM_DATA_WIDTH_CLOG:0] spi_buffer_fill = 0;
logic spi_load_buffer = 1'b0;
logic spi_clock_enabled = 1'b0;

wire [MEM_DATA_WIDTH_CLOG:0] mem_data_width_cycles = spi_quad_mode ? MEM_DATA_WIDTH/4 : MEM_DATA_WIDTH;

xpm_cdc_handshake#(
    .DEST_EXT_HSK(1),
    .WIDTH(MEM_DATA_WIDTH),
    .SIM_ASSERT_CHK(1)
) cdc_dma_read_info(
    .src_clk(cpu_clock_i),
    .src_in(cpu_dma_read_data),
    .src_send(cpu_dma_read_valid),
    .src_rcv(cpu_dma_read_ack),

    .dest_clk(spi_ref_clock_i),
    .dest_out(spi_dma_read_data),
    .dest_req(spi_dma_read_valid),
    .dest_ack(spi_dma_read_ack)
), cdc_dma_write_info(
    .src_clk(spi_ref_clock_i),
    .src_in(spi_shift_buffer),
    .src_send(spi_dma_write_valid),
    .src_rcv(spi_dma_write_ack),

    .dest_clk(cpu_clock_i),
    .dest_out(cpu_dma_write_data),
    .dest_req(cpu_dma_write_valid),
    .dest_ack(cpu_dma_write_ack)
);

always_comb begin
    spi_state_next = spi_state;

    case(spi_state)
        IDLE: begin
            if( spi_dma_read_valid && !spi_dma_read_ack ) begin
                spi_state_next = SEND_STARTING;
            end
        end
        SEND_STARTING: begin
            spi_state_next = SEND_ACTIVE;
        end
        SEND_ACTIVE: begin
            if( spi_send_cycles==0 ) begin
                // Send part done
                if( spi_dummy_cycles!=0 )
                    spi_state_next = DUMMY;
                else if( spi_recv_cycles!=0 ) begin
                    spi_state_next = RECV_ACTIVE;
                end else
                    spi_state_next = IDLE;
            end else begin
                // Send part not done
                if( spi_buffer_fill==0 ) begin
                    spi_state_next = SEND_PENDING;
                end
            end
        end
        SEND_PENDING: begin
            if( spi_dma_read_valid && !spi_dma_read_ack )
                spi_state_next = SEND_ACTIVE;
        end
        DUMMY: begin
            if( spi_dummy_cycles==0 ) begin
                if( spi_recv_cycles!=0 )
                    spi_state_next = RECV_ACTIVE;
                else
                    spi_state_next = IDLE;
            end
        end
        RECV_ACTIVE: begin
            if( spi_recv_cycles==0 ) begin
                spi_state_next = IDLE_PENDING;
            end else if( spi_buffer_fill==mem_data_width_cycles ) begin
                spi_state_next = RECV_PENDING;
            end
        end
        RECV_PENDING: begin
            if( spi_dma_write_valid && spi_dma_write_ack )
                spi_state_next = RECV_ACTIVE;
        end
        IDLE_PENDING: begin
            if( spi_dma_write_valid && spi_dma_write_ack )
                spi_state_next = IDLE;
        end
    endcase
end

task ack_buffer_from_cpu(input new_transaction);
    if( new_transaction )
        spi_buffer_fill <= spi_num_send_cycles<mem_data_width_cycles ? spi_num_send_cycles : mem_data_width_cycles;
    else
        spi_buffer_fill <= spi_send_cycles<mem_data_width_cycles ? spi_send_cycles : mem_data_width_cycles;

    spi_dma_read_ack <= 1'b1;
endtask

always_ff@(posedge spi_ref_clock_i) begin
    spi_state <= spi_state_next;

    if( spi_dma_read_ack && !spi_dma_read_valid )
        spi_dma_read_ack <= 1'b0;

    if( spi_dma_write_valid && spi_dma_write_ack )
        spi_dma_write_valid <= 1'b0;

    case( spi_state_next )
        IDLE: begin
            spi_buffer_fill <= 0;
        end
        SEND_STARTING: begin
            spi_send_cycles <= spi_num_send_cycles;
            spi_recv_cycles <= spi_num_recv_cycles;
            spi_dummy_cycles <= spi_transfer_mode[15:0];
            spi_quad_mode <= spi_transfer_mode[16];

            ack_buffer_from_cpu(1'b1);
        end
        SEND_ACTIVE: begin
            spi_send_cycles <= spi_send_cycles - 1;
            spi_buffer_fill <= spi_buffer_fill - 1;

            if( spi_state==SEND_PENDING ) begin
                ack_buffer_from_cpu(1'b0);
            end
        end
        DUMMY: begin
            spi_dummy_cycles <= spi_dummy_cycles - 1;
        end
        RECV_ACTIVE: begin
            spi_recv_cycles <= spi_recv_cycles - 1;
            spi_buffer_fill <= spi_buffer_fill + 1;
        end
        RECV_PENDING: begin
            spi_buffer_fill <= 0;

            if( !spi_dma_write_ack )
                spi_dma_write_valid <= 1'b1;
        end
        IDLE_PENDING: begin
            if( !spi_dma_write_ack )
                spi_dma_write_valid <= 1'b1;
        end
    endcase
end

BUFGCE spi_clock_buf(
    .O(spi_clk_o),
    .I(spi_ref_clock_i),
    .CE(spi_clock_enabled)
);

logic[3:0] spi_dq_dir = 4'b1111;
logic[3:0] spi_dq_o = 4'b1100, spi_dq_i;

always_ff@(negedge spi_ref_clock_i) begin
    if( spi_state_next[2] ) begin
        // Send mode
        if( spi_quad_mode ) begin
            spi_dq_o <= {spi_shift_buffer[0], spi_shift_buffer[1], spi_shift_buffer[2], spi_shift_buffer[3]};
            spi_dq_dir <= 4'b0000;
        end else begin
            spi_dq_o <= {3'b11X, spi_shift_buffer[0]};
            spi_dq_dir <= 4'b0010;
        end
    end else begin
        // Non send mode
        spi_dq_o <= 4'b11X1;
        if( spi_quad_mode )
            spi_dq_dir <= 4'b1111;
        else
            spi_dq_dir <= 4'b0011;
    end

    spi_clock_enabled <= spi_state_next[1];
    spi_load_buffer <= spi_state_next[4];
end

assign spi_cs_n_o = spi_state[0];

generate

for( i=0; i<4; ++i )
    IOBUF dq_buffer(.T(spi_dq_dir[i]), .I(spi_dq_o[i]), .O(spi_dq_i[i]), .IO(spi_dq_io[i]));

endgenerate

generate

for( i=0; i<1; ++i ) begin
    always_ff@(posedge spi_ref_clock_i) begin
        if( spi_load_buffer ) begin
            spi_shift_buffer[i] <= spi_dma_read_data[i];
        end else begin
            case(spi_state_next)
                SEND_ACTIVE: spi_shift_buffer[i] <= (spi_quad_mode ? spi_shift_buffer[i+4] : spi_shift_buffer[i+1]);
                RECV_ACTIVE: spi_shift_buffer[i] <= (spi_quad_mode ? spi_dq_i[0] : spi_dq_i[1]);
                DUMMY: spi_shift_buffer[i] <= 1'bX;
            endcase
        end
    end
end

for( i=1; i<4; ++i ) begin
    always_ff@(posedge spi_ref_clock_i) begin
        if( spi_load_buffer ) begin
            spi_shift_buffer[i] <= spi_dma_read_data[i];
        end else begin
            case(spi_state_next)
                SEND_ACTIVE: spi_shift_buffer[i] <= (spi_quad_mode ? spi_shift_buffer[i+4] : spi_shift_buffer[i+1]);
                RECV_ACTIVE: spi_shift_buffer[i] <= (spi_quad_mode ? spi_dq_i[i] : spi_shift_buffer[i-1]);
                DUMMY: spi_shift_buffer[i] <= 1'bX;
            endcase
        end
    end
end

for( i=4; i<(MEM_DATA_WIDTH-4); ++i ) begin
    always_ff@(posedge spi_ref_clock_i) begin
        if( spi_load_buffer ) begin
            spi_shift_buffer[i] <= spi_dma_read_data[i];
        end else begin
            case(spi_state_next)
                SEND_ACTIVE: spi_shift_buffer[i] <= (spi_quad_mode ? spi_shift_buffer[i+4] : spi_shift_buffer[i+1]);
                RECV_ACTIVE: spi_shift_buffer[i] <= (spi_quad_mode ? spi_shift_buffer[i-4] : spi_shift_buffer[i-1]);
                DUMMY: spi_shift_buffer[i] <= 1'bX;
            endcase
        end
    end
end

for( i=MEM_DATA_WIDTH-4; i<(MEM_DATA_WIDTH-1); ++i ) begin
    always_ff@(posedge spi_ref_clock_i) begin
        if( spi_load_buffer ) begin
            spi_shift_buffer[i] <= spi_dma_read_data[i];
        end else begin
            case(spi_state_next)
                SEND_ACTIVE: spi_shift_buffer[i] <= (spi_quad_mode ? 1'bX : spi_shift_buffer[i+1]);
                RECV_ACTIVE: spi_shift_buffer[i] <= (spi_quad_mode ? spi_shift_buffer[i-4] : spi_shift_buffer[i-1]);
                DUMMY: spi_shift_buffer[i] <= 1'bX;
            endcase
        end
    end
end

for( i=MEM_DATA_WIDTH-1; i<MEM_DATA_WIDTH; ++i ) begin
    always_ff@(posedge spi_ref_clock_i) begin
        if( spi_load_buffer ) begin
            spi_shift_buffer[i] <= spi_dma_read_data[i];
        end else begin
            case(spi_state_next)
                SEND_ACTIVE: spi_shift_buffer[i] <= 1'bX;
                RECV_ACTIVE: spi_shift_buffer[i] <= (spi_quad_mode ? spi_shift_buffer[i-4] : spi_shift_buffer[i-1]);
                DUMMY: spi_shift_buffer[i] <= 1'bX;
            endcase
        end
    end
end

endgenerate

assign debug[0] = spi_clk_o;
assign debug[1] = spi_cs_n_o;
assign debug[2] = spi_dq_i[0];
assign debug[3] = spi_dq_i[1];

endmodule
