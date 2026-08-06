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
    input ctrl_req_valid_i,
    output ctrl_req_ack_o,
    input [15:0] ctrl_req_addr_i,
    input ctrl_req_write_i,
    input [31:0] ctrl_req_write_data_i,

    output logic ctrl_rsp_valid_o = 1'b0,
    output logic [31:0] ctrl_rsp_read_data_o,

    // 8 bit CPU interface
    input cpu_req_valid_i,
    output cpu_req_ack_o,
    input cpu_req_write_i,
    input [7:0] cpu_req_write_data_i,

    output cpu_rsp_valid_o,
    output [7:0] cpu_rsp_write_data_o,

    // Sniff the apple's bus to know when a valid bus cycle has taken place.
    input cpu_bus_valid_i,
    input cpu_bus_ack_i,

    // DMA interface
    output dma_req_valid_o,
    input dma_req_ack_i,
    output [31:0] dma_req_addr_o,
    output [(DMA_WIDTH/8)-1:0] dma_req_write_mask_o,
    output [DMA_WIDTH-1:0] dma_req_write_data_o,

    input dma_rsp_valid_i,
    input [DMA_WIDTH-1:0] dma_rsp_read_data_i
    );

logic [31:0] spin_counter, spin_increment;
logic [31:0] track_base_addr, track_current_addr;

assign ctrl_req_ack_o = 1'b1;

always_ff@(posedge clk_i) begin
    ctrl_rsp_valid_o = 1'b0;

    if( ctrl_req_valid_i && ctrl_req_ack_o ) begin
        if( ctrl_req_write_i ) begin
            case( ctrl_req_addr_i )
                16'h0000: begin end
            endcase
        end else begin
            ctrl_rsp_valid_o = 1'b1;
            ctrl_rsp_read_data_o = 32'hX;
        end
    end
end

endmodule
