`timescale 1ns / 1ps

module timer_int_ctrl#(
    parameter CLOCK_HZ=50000000
)
(
    input clock,

    // Request
    input [15:0]        req_addr_i,
    input [31:0]        req_data_i,
    input               req_write_i,
    input               req_valid_i,
    output logic        req_ready_o,

    // Response
    output logic[31:0]  rsp_data_o,
    output logic        rsp_valid_o,

    // IRQ lines
    input [31:0]        irqs_i,

    // Control lines
    output logic        ctrl_timer_interrupt_o,
    output logic        ctrl_ext_interrupt_o,
    input               ctrl_software_interrupt_i
);

/*
* Registers:
*       Sequential interface:
*       0000 Wait until time point is reached or interrupt (R)
*       0004 Report clock's frequency (R)
*       0008 Current cycle count low, latch high (R)
*       000c Latched cycle count high (R)
*       0010 Wait cycle low (RW)
*       0014 Wait cycle high (RW)
*
*       Timer interrupt interface
*       0200 Interrupt cycle low (RW)
*       0204 Interrupt cycle high (latched) (RW)
*       0210 Reset interrupt cycle (W)
*
*       IRQ control
*       0400 Active IRQs
*       0500 Set IRQs mask (write 1 to set)
*       0580 Clear IRQs mask (write 1 to clear)
*/

logic[63:0] wait_cycle, wait_cycle_next;
logic[31:0] pending_address, pending_address_next;
logic prev_valid = 1'b0, prev_valid_next;

// Sequential interface
logic[63:0] cycles_counter = 64'h0;
logic[31:0] cycles_counter_saved;
logic       cycles_counter_save_flag;

// Timer interrupt interface
localparam TIMER_INT_DISABLED32 = 32'hffffffff;
localparam TIMER_INT_DISABLED64 = 64'hffffffffffffffff;
logic[63:0] interrupt_cycle = TIMER_INT_DISABLED64, interrupt_cycle_next;
logic[31:0] interrupt_cycle_high_latch = TIMER_INT_DISABLED32, interrupt_cycle_high_latch_next;

// IRQs
logic[31:0] irq_active = 0, irq_masked = 32'hffffffff, irq_masked_next;
assign ctrl_ext_interrupt_o = (irq_active & (~irq_masked)) != 0;

always_ff@(posedge clock) begin
    irq_active <= irqs_i;

    cycles_counter <= cycles_counter+1;

    prev_valid <= prev_valid_next;
    pending_address <= pending_address_next;

    irq_masked <= irq_masked_next;

    if( cycles_counter_save_flag )
        cycles_counter_saved <= cycles_counter[63:32];

    // XXX assigns every cycle. Can possibly lower power consumption by making
    // assignment conditional
    wait_cycle <= wait_cycle_next;
    interrupt_cycle <= interrupt_cycle_next;
    interrupt_cycle_high_latch <= interrupt_cycle_high_latch_next;

    ctrl_timer_interrupt_o <= (cycles_counter >= interrupt_cycle) ? 1'b1 : 1'b0;
end

always_comb begin
    // Keep state for next cycle

    if( req_valid_i && req_ready_o ) begin
        if( req_write_i ) begin
            prev_valid_next = prev_valid;
            pending_address_next = pending_address;
        end else begin
            pending_address_next = req_addr_i;
            prev_valid_next = 1'b1;
        end
    end else if( prev_valid && !rsp_valid_o ) begin
        prev_valid_next = 1'b1;
        pending_address_next = pending_address;
    end else begin
        prev_valid_next = 1'b0;
        pending_address_next = 32'hX;
    end
end

logic wait_expired;

always_ff@(posedge clock) begin
    wait_expired <= (wait_cycle <= cycles_counter);
end

always_comb begin
    // Handle response
    cycles_counter_save_flag = 1'b0;
    rsp_data_o = 32'hX;
    rsp_valid_o = 1'bX;

    if( prev_valid ) begin
        rsp_valid_o = 1'b1;
        case( pending_address )
            16'h0000: begin     // Halt
                if(!wait_expired && !ctrl_timer_interrupt_o && !ctrl_ext_interrupt_o && !ctrl_software_interrupt_i) begin
                    rsp_valid_o = 1'b0;
                end else begin
                    rsp_valid_o = 1'b1;
                    rsp_data_o = cycles_counter[31:0];
                    cycles_counter_save_flag = 1'b1;
                end
            end
            16'h0004:           // Clock frequency
                rsp_data_o = CLOCK_HZ;
            16'h0008: begin     // Cycle count low
                rsp_data_o = cycles_counter[31:0];
                cycles_counter_save_flag = 1'b1;
            end
            16'h000c:           // Cycle count high
                rsp_data_o = cycles_counter_saved;
            16'h0010:           // Wait cycle low
                rsp_data_o = wait_cycle[31:0];
            16'h0014:           // Wait cycle high
                rsp_data_o = wait_cycle[63:32];
            16'h0200:
                rsp_data_o = interrupt_cycle[31:0];
            16'h0204:
                rsp_data_o = interrupt_cycle[63:32];
            16'h0400:
                rsp_data_o = irq_active & (~irq_masked);
            16'h0500:
                rsp_data_o = irq_masked;
            16'h0580:
                rsp_data_o = irq_masked;
            default:
                rsp_data_o = 32'h0;
        endcase
    end
end

always_comb begin
    // Handle request

    req_ready_o = 1'bX;
    wait_cycle_next = wait_cycle;
    interrupt_cycle_next = interrupt_cycle;
    interrupt_cycle_high_latch_next = interrupt_cycle_high_latch;
    irq_masked_next = irq_masked;

    if( req_valid_i ) begin
        req_ready_o = 1'b1;  // Accept request by default

        if( req_write_i ) begin
            // Write
            case(req_addr_i)
                16'h0010: // Wait cycle low
                    wait_cycle_next[31:0] = req_data_i;
                16'h0014: // Wait cycle high
                    wait_cycle_next[63:32] = req_data_i;
                16'h0200: // Interrupt cycle low
                    interrupt_cycle_next = { interrupt_cycle_high_latch, req_data_i };
                16'h0204: // Interrupt cycle high
                    interrupt_cycle_high_latch_next = req_data_i;
                16'h0210: // Reset timer interrupt
                    interrupt_cycle_next = TIMER_INT_DISABLED64;
                16'h0214: // Reset wait cycles
                    wait_cycle_next = TIMER_INT_DISABLED64;
                16'h0500: // Set bits in IRQ mask
                    irq_masked_next = irq_masked | req_data_i;
                16'h0580: // Clear bits in IRQ mask
                    irq_masked_next = irq_masked & ~req_data_i;
            endcase
        end
    end
end

endmodule
