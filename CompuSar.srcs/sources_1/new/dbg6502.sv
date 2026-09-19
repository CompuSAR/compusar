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
    input[7:0]          cpu_reg_a,
    input[7:0]          cpu_reg_x,
    input[7:0]          cpu_reg_y,
    input[7:0]          cpu_reg_s,
    input[7:0]          cpu_reg_p,

    sync_bus.SLAVE      ctrl,

    output logic        halt_o,


    output [1:0]        internal_debug_o
);

localparam NUM_BREAKPOINT = 4;

assign ctrl.req_ack = 1'b1;

typedef struct packed {
    bit vector_pull;
    bit memlock;
    bit sync;
    bit write;
} tracked_signals;

typedef struct packed {
    tracked_signals     sig_mask;
    tracked_signals     sig_state;
    bit[7:0]            value;
    bit[15:0]           address;
} breakpoint;

tracked_signals current_state;
assign current_state.write = cpu_req_write_i;
assign current_state.sync = cpu_sync_i;
assign current_state.memlock = cpu_memlock_i;
assign current_state.vector_pull = cpu_vector_pull_i;

logic[NUM_BREAKPOINT-1:0] breakpoint_hit;
breakpoint breakpoints[NUM_BREAKPOINT];

logic singlestep = 1'b0, cont = 1'b0, halt = 1'b0;

always_ff@(posedge clk_i) begin
    ctrl.rsp_valid <= 1'b0;

    if( cont && cpu_req_valid_i && cpu_req_ack_i ) begin
        cont <= 1'b0;
    end

    // If a breakpoint was hit, halt regardless of that breakpoint's current
    // status
    if( breakpoint_hit!={NUM_BREAKPOINT{1'b0}} )
        halt <= 1'b1;

    if( ctrl.req_valid && ctrl.req_ack ) begin
        if( ctrl.req_write ) begin
            // Control CPU write
            case( ctrl.req_addr )
                16'h0000: { singlestep, halt, cont } <= ctrl.req_data[2:0];
                16'h8000: breakpoints[0] <= ctrl.req_data;
                16'h8004: breakpoints[1] <= ctrl.req_data;
                16'h8008: breakpoints[2] <= ctrl.req_data;
                16'h800c: breakpoints[3] <= ctrl.req_data;
            endcase
        end else begin
            // Control CPU read
            case( ctrl.req_addr )
                16'h0000: ctrl.rsp_data <= { halt_o, 27'h00, breakpoint_hit };
                16'h0004: begin
                    breakpoint bp;
                    bp.address = cpu_req_addr_i;
                    bp.value = cpu_req_write_data_i;
                    bp.sig_state = current_state;
                    bp.sig_mask = breakpoint_hit;

                    ctrl.rsp_data <= bp;
                end
                16'h0010: ctrl.rsp_data <= { 24'h0, cpu_reg_a };
                16'h0014: ctrl.rsp_data <= { 24'h0, cpu_reg_x };
                16'h0018: ctrl.rsp_data <= { 24'h0, cpu_reg_y };
                16'h001c: ctrl.rsp_data <= { 24'h0, cpu_reg_s };
                16'h0020: ctrl.rsp_data <= { 24'h0, cpu_reg_p };
                default:
                    ctrl.rsp_data <= 32'hX;
            endcase

            ctrl.rsp_valid <= 1'b1;
        end
    end
end

always_comb begin
    if( cont )
        // Control requested we continue
        halt_o = 1'b0;
    else if( breakpoint_hit!={NUM_BREAKPOINT{1'b0}} )
        // A breakpoint was hit
        halt_o = 1'b1;
    else if( halt )
        // Control requested we halt
        halt_o = 1'b1;
    else if( singlestep && cpu_req_valid_i && cpu_sync_i )
        // Instruction execution while we single step
        halt_o = 1'b1;
    else
        // No reason to halt
        halt_o = 1'b0;
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

assign internal_debug_o[0] = cont;
assign internal_debug_o[1] = halt_o;

endmodule
