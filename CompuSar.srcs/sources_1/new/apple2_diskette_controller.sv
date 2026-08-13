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


module apple2_diskette_controller#(
    DMA_WIDTH = 128
)(
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

    output cpu_rsp_valid_o,
    output [7:0] cpu_rsp_read_data_o,

    // Sniff the apple's bus to know when a valid bus cycle has taken place.
    input cpu_bus_valid_i,
    input cpu_bus_ack_i,

    // DMA interface
    sync_bus_write_mask.MASTER dma
    );

initial assign dma.req_valid = 1'b0;

logic [31:0] spin_counter, spin_increment;
logic [31:0] track_base_addr, track_current_addr;

assign ctrl.req_ack = 1'b1;

always_ff@(posedge clk_i) begin
    ctrl.rsp_valid = 1'b0;

    if( ctrl.req_valid && ctrl.req_ack ) begin
        if( ctrl.req_write ) begin
            case( ctrl.req_addr )
                16'h0000: begin end
            endcase
        end else begin
            ctrl.rsp_valid = 1'b1;
            ctrl.rsp_data = 32'hX;
        end
    end
end

endmodule
