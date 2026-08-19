`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/18/2026 04:31:49 PM
// Design Name: 
// Module Name: dbg6502
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


module dbg6502(
    input               clk_i,

    input               cpu_req_valid_i,
    input               cpu_req_ack_i,
    input               cpu_req_write_i,
    input[15:0]         cpu_req_addr_i,
    input[7:0]          cpu_req_write_data_i,

    input               cpu_sync_i,
    input               cpu_memlock_i,
    input               cpu_vector_pull_i,

    sync_bus.SLAVE      ctrl,
    output              ctrl_intr_o,

    output              n_halt_o
);

localparam NUM_BREAKPOINT = 4;

assign ctrl.req_ack = 1'b1;
assign n_halt_o = breakpoint_hit == 0;
assign ctrl_intr_o = n_halt_o;

typedef struct packed {
    bit write;
    bit sync;
    bit memlock;
    bit vector_pull;
} tracked_signals;

typedef struct packed {
    bit[15:0]           address;
    bit[7:0]            value;
    tracked_signals     sig_state;
    tracked_signals     sig_mask;
} breakpoint;

tracked_signals current_state;
assign current_state.write = cpu_req_write_i;
assign current_state.sync = cpu_sync_i;
assign current_state.memlock = cpu_memlock_i;
assign current_state.vector_pull = cpu_vector_pull_i;

logic[NUM_BREAKPOINT-1:0] breakpoint_hit;
breakpoint breakpoints[NUM_BREAKPOINT];

always_ff@(posedge clk_i) begin
    ctrl.rsp_valid <= 1'b0;

    if( ctrl.req_valid && ctrl.req_ack ) begin
        if( ctrl.req_write ) begin
            // Control CPU write
            case( ctrl.req_addr )
                16'h0000: begin /* Stop/start the 6502 */ end
                16'h8000: breakpoints[0] <= ctrl.req_data;
                16'h8004: breakpoints[1] <= ctrl.req_data;
                16'h8008: breakpoints[2] <= ctrl.req_data;
                16'h800c: breakpoints[3] <= ctrl.req_data;
            endcase
        end else begin
            // Control CPU read
            case( ctrl.req_addr )
                16'h0000: ctrl.rsp_data <= { !n_halt_o, 27'h00, breakpoint_hit };
                16'h0004: begin
                    breakpoint bp;
                    bp.address = cpu_req_addr_i;
                    bp.value = cpu_req_write_data_i;
                    bp.sig_state = current_state;
                    bp.sig_mask = breakpoint_hit;

                    ctrl.rsp_data <= bp;
                end
                default:
                    ctrl.rsp_data <= 32'hX;
            endcase

            ctrl.rsp_valid <= 1'b1;
        end
    end
end

genvar i;

generate

for( i=0; i<NUM_BREAKPOINT; i++ ) begin
    initial breakpoints[i].sig_state = 4'b1111;
    initial breakpoints[i].sig_mask = 4'b1111;
end

for( i=0; i<NUM_BREAKPOINT; i++ ) begin
    assign breakpoint_hit[i] =
        cpu_req_valid_i &&
        cpu_req_addr_i == breakpoints[i].address &&
        ( current_state & breakpoints[i].sig_mask) == breakpoints[i].sig_state;
end

endgenerate

endmodule
