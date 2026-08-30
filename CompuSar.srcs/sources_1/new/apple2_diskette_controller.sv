`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/05/2026 10:14:35 AM
// Design Name: 
// Module Name: apple2_diskette_controller
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


module apple2_diskette_controller(
    input clk_i,
    input reset_i,

    // Control CPU interface
    sync_bus.SLAVE ctrl,

    // 8 bit CPU interface
    input cpu_req_valid_i,
    output cpu_req_ack_o,
    input [15:0] cpu_req_addr_i,
    input cpu_req_write_i,
    input [7:0] cpu_req_write_data_i,

    output logic cpu_rsp_valid_o = 1'b0,
    output logic[7:0] cpu_rsp_read_data_o,

    // Sniff the apple's bus to know when a valid bus cycle has taken place.
    input cpu_bus_valid_i,
    input cpu_bus_ack_i,

    // DMA interface
    sync_bus_write_mask.MASTER dma
    );

localparam DMA_WIDTH = $bits(dma.req_data);
localparam DMA_WIDTH_BYTES = DMA_WIDTH / 8;
localparam DMA_WIDTH_ADDR = $clog2(DMA_WIDTH);

localparam REG_FULL_READ_GRACE = 10;

initial dma.req_valid = 1'b0;

wire apple_cycle;
assign apple_cycle = cpu_bus_valid_i && cpu_bus_ack_i;

logic [31:0] spin_counter, spin_increment;

logic [31:0] track_data_start, track_data_length, track_pos, track_pos_next, fetch_offset;
logic [15:0] bit_ratio_num, bit_ratio_denom;
logic motor_running = 1'b0, freq_div_reset = 1'b1, no_disk_in_drive = 1'b1;

assign track_pos_next = track_pos + 1;

logic [DMA_WIDTH-1:0] dma_data[2] = '{ default: {DMA_WIDTH{1'b0}} };
logic dma_data_valid[2] = '{ default: 1'b0 };
logic dma_req_pending = 1'b0;

logic [7:0] shift_register = 8'h00;
logic [$clog2(REG_FULL_READ_GRACE)-1:0] grace_counter;
logic should_bit_shift;
wire next_bit_in;

assign next_bit_in = no_disk_in_drive ? 1'b0 : dma_data[0][track_pos[DMA_WIDTH_ADDR-1:0]];

assign ctrl.req_ack = 1'b1;
assign cpu_req_ack_o = 1'b1;

always_ff@(posedge clk_i) begin
    ctrl.rsp_valid <= 1'b0;

    // CTRL CPU requests
    if( ctrl.req_valid && ctrl.req_ack ) begin
        if( ctrl.req_write ) begin
            case( ctrl.req_addr )
                16'h0000: begin
                    track_data_start <= ctrl.req_data;
                    dma_data_valid <= '{ default: 1'b0 };
                end
                16'h0004: begin
                    track_data_length <= ctrl.req_data;
                    dma_data_valid <= '{ default: 1'b0 };
                end
                16'h0008: begin
                    track_pos <= ctrl.req_data;
                    fetch_offset <= { ctrl.req_data[31:DMA_WIDTH_ADDR], {(DMA_WIDTH_ADDR-3){1'b0}} };

                    shift_register <= 8'h00;
                    grace_counter <= 0;

                    dma_data_valid <= '{ default: 1'b0 };
                end
                16'h000c: begin
                    { bit_ratio_num, bit_ratio_denom } <= ctrl.req_data;
                end
                16'h0010: begin
                    { freq_div_reset, motor_running } <= ctrl.req_data[1:0];
                end
                16'h0014: begin
                    { no_disk_in_drive } <= ctrl.req_data[0:0];
                end
            endcase
        end else begin
            // Read
            case( ctrl.req_addr )
                16'h0004:
                    ctrl.rsp_data <= track_data_length;
                16'h0008:
                    ctrl.rsp_data <= track_pos;
                default:
                    ctrl.rsp_data <= 32'hX;
            endcase
            ctrl.rsp_valid <= 1'b1;
        end
    end

    // DMA handling
    if( {fetch_offset, 3'b000} >= track_data_length )
        fetch_offset <= 0;

    if( !motor_running || no_disk_in_drive ) begin
        dma.req_valid <= 1'b0;
        dma_data_valid <= '{ default: 1'b0 };
    end else begin
        if( dma.req_valid && dma.req_ack ) begin
            dma.req_valid <= 1'b0;
            dma_req_pending <= 1'b1;
        end
        if( !dma.req_valid && !dma_req_pending && !dma_data_valid[1] ) begin
            dma.req_valid <= 1'b1;
            dma.req_write_mask <= 0;
            dma.req_addr <= track_data_start + fetch_offset;
            fetch_offset <= fetch_offset + DMA_WIDTH_BYTES;
        end
        if( dma_req_pending && dma.rsp_valid ) begin
            dma_data[1] <= dma.rsp_data;
            dma_data_valid[1] <= 1'b1;
            dma_req_pending <= 1'b0;
        end
    end

    if( dma_data_valid[1] && !dma_data_valid[0] ) begin
        dma_data_valid[0] <= 1'b1;
        dma_data_valid[1] <= 1'b0;
        dma_data[0] <= dma_data[1];
    end

    // Shift buffer handling
    if( apple_cycle && grace_counter!=0 ) begin
        grace_counter <= grace_counter - 1;
    end

    if( should_bit_shift ) begin
        if( track_pos_next == track_data_length )
            track_pos <= 0;
        else
            track_pos <= track_pos_next;

        if( track_pos_next[DMA_WIDTH_ADDR-1:0] == 0 )
            dma_data_valid[0] <= 1'b0;

        if( shift_register[7] ) begin
            shift_register <= { 7'b0000000, next_bit_in };
        end else begin
            shift_register <= { shift_register[6:0], next_bit_in };

            if( shift_register[6] ) begin
                // We're going to be full post shift
                grace_counter <= REG_FULL_READ_GRACE - 1;
            end
        end
    end

    // Apple CPU interface
    cpu_rsp_valid_o <= 1'b0;

    if( cpu_req_valid_i && cpu_req_ack_o ) begin
        if( cpu_req_write_i ) begin
        end else begin
            // Read request
            if( motor_running )
                cpu_rsp_read_data_o <= shift_register;
            else
                cpu_rsp_read_data_o <= 8'h00;

            cpu_rsp_valid_o <= 1'b1;
        end
    end
end

/*
* Our base cycles are the apple cycles (so, those control CPU cycles where the
* Apple CPU is allowed to also have a tick). We thus set the clock_enable_i
* accordingly.
*
* We are considered "wanting to have a bus operation" if we have valid data,
* hence the slow_cmd_valid_i input.
*
* The "downstream device" is considered ready for a transaction only if our
* grace counter doesn't say we need to freeze. This sets fast_cmd_ready_i.
* If the grace counter does tell us to freeze, this module will keep track and
* catch up immediately after it unfreezes.
*
* slow_cmd_ready_o tells us that our apple cycles divided by the divisor
* allows a new bit to come in. fast_cmd_valid_o combines that with actual data
* being available.
*/
freq_div_bus bits_tracker(
    .clock_i(clk_i),
    .reset_i(freq_div_reset || !motor_running),

    .clock_enable_i(apple_cycle ),

    .ctl_div_nom_i(bit_ratio_num),
    .ctl_div_denom_i(bit_ratio_denom),

    .slow_cmd_valid_i(dma_data_valid[0]),
    .slow_cmd_ready_o(),

    .fast_cmd_valid_o(should_bit_shift),
    .fast_cmd_ready_i(grace_counter == 0)
);

endmodule
