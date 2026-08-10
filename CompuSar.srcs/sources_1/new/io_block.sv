`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/27/2022 04:45:40 PM
// Design Name: 
// Module Name: io_block
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


module io_block(
    input clock,

    sync_bus_write_mask.SLAVE cpu_port,
    output logic rsp_error,

    sync_bus_write_mask.MASTER ddr_port,

    output logic passthrough_ddr_ctrl_enable,
    input passthrough_ddr_ctrl_req_ack,
    input passthrough_ddr_ctrl_rsp_valid,
    input [31:0] passthrough_ddr_ctrl_data,

    output logic passthrough_gpio_enable,
    input passthrough_gpio_req_ack,
    input passthrough_gpio_rsp_valid,
    input [31:0] passthrough_gpio_rsp_data,

    output logic passthrough_irq_enable,
    input passthrough_irq_req_ack,
    input passthrough_irq_rsp_valid,
    input [31:0] passthrough_irq_rsp_data,

    output logic passthrough_spi_enable,
    input passthrough_spi_req_ack,
    input passthrough_spi_rsp_valid,
    input [31:0] passthrough_spi_rsp_data,

    output logic passthrough_uart_enable,
    input passthrough_uart_req_ack,
    input passthrough_uart_rsp_valid,
    input [31:0] passthrough_uart_rsp_data,

    output logic passthrough_sd_enable,
    input passthrough_sd_req_ack,
    input passthrough_sd_rsp_valid,
    input [31:0] passthrough_sd_rsp_data,

    output logic passthrough_display_enable,
    input passthrough_display_req_ack,
    input passthrough_display_rsp_valid,
    input [31:0] passthrough_display_rsp_data,

    output logic passthrough_dbglogger_enable,
    input passthrough_dbglogger_req_ack,
    input passthrough_dbglogger_rsp_valid,
    input [31:0] passthrough_dbglogger_rsp_data
);

logic write;
assign write = cpu_port.req_write_mask != 0;

logic [31:0] previous_address, previous_address_next;
logic previous_valid=1'b0;

always_comb begin
    // The ports that get forwarded with no logic
    ddr_port.req_addr = cpu_port.req_addr;
    ddr_port.req_data = cpu_port.req_data;
    ddr_port.req_write_mask = cpu_port.req_write_mask;
end

always_ff@(posedge clock) begin
    previous_address <= previous_address_next;

    if( previous_valid && !cpu_port.rsp_valid )
        // Previous cycle still waiting for response. Don't advance.
        previous_valid <= 1'b1;
    else if( cpu_port.req_valid && cpu_port.req_ack )
        previous_valid = !write;
    else
        previous_valid = 1'b0;
end

logic uart_send_data_ready;
logic uart_recv_ready;

task default_state_current();
    uart_send_data_ready = 1'b0;
    cpu_port.req_ack = 1'b1;
    previous_address_next = cpu_port.req_addr;

    ddr_port.req_valid = 1'b0;

    passthrough_uart_enable = 1'b0;
    passthrough_ddr_ctrl_enable = 1'b0;
    passthrough_gpio_enable = 1'b0;
    passthrough_irq_enable = 1'b0;
    passthrough_spi_enable = 1'b0;
    passthrough_display_enable = 1'b0;
    passthrough_dbglogger_enable = 1'b0;
    passthrough_sd_enable = 1'b0;
endtask

function logic is_ddr(logic [31:0]address);
    is_ddr = address[31:30] == 2'b10;
endfunction

function logic is_io(logic [31:0]address);
    is_io = address[31:30] == 2'b11;
endfunction

always_comb begin
    // Previous cycle analysis
    cpu_port.rsp_valid = 1'bX;
    rsp_error = 1'b0;
    cpu_port.rsp_data = 32'bX;

    if( previous_valid ) begin
        if( is_ddr(previous_address) ) begin
            cpu_port.rsp_data = ddr_port.rsp_data;
            cpu_port.rsp_valid = ddr_port.rsp_valid;
        end else begin
            case( previous_address[23:16] )
                8'h0: begin                     // UART
                    cpu_port.rsp_valid = passthrough_uart_rsp_valid;
                    cpu_port.rsp_data = passthrough_uart_rsp_data;
                end
                8'h1: begin                     // DDR control
                    cpu_port.rsp_valid = passthrough_ddr_ctrl_rsp_valid;
                    cpu_port.rsp_data = passthrough_ddr_ctrl_data;
                end
                8'h2: begin                     // GPIO
                    cpu_port.rsp_valid = passthrough_gpio_rsp_valid;
                    cpu_port.rsp_data = passthrough_gpio_rsp_data;
                end
                8'h3: begin                     // Interrupt controller
                    cpu_port.rsp_valid = passthrough_irq_rsp_valid;
                    cpu_port.rsp_data = passthrough_irq_rsp_data;
                end
                8'h4: begin                     // SPI controller
                    cpu_port.rsp_valid = passthrough_spi_rsp_valid;
                    cpu_port.rsp_data = passthrough_spi_rsp_data;
                end
                8'h5: begin                     // Display controller
                    cpu_port.rsp_valid = passthrough_display_rsp_valid;
                    cpu_port.rsp_data = passthrough_display_rsp_data;
                end
                8'h6: begin                     // SD
                    cpu_port.rsp_valid = passthrough_sd_rsp_valid;
                    cpu_port.rsp_data = passthrough_sd_rsp_data;
                end
                8'h10: begin                     // Debug logger
                    cpu_port.rsp_valid = passthrough_dbglogger_rsp_valid;
                    cpu_port.rsp_data = passthrough_dbglogger_rsp_data;
                end
                default: begin                  // Invalid memory access
                    cpu_port.rsp_valid = 1'b1;
                    rsp_error = 1'b1;
                end
            endcase
        end
    end
end

always_comb begin
    default_state_current();

    // Current cycle analysis
    if( previous_valid && !cpu_port.rsp_valid ) begin
        // Previous cycle still waiting for response. Don't advance.
        previous_address_next = previous_address;
        cpu_port.req_ack = 1'b0;
    end else begin
        if( is_ddr(cpu_port.req_addr) ) begin
            ddr_port.req_valid = cpu_port.req_valid;
            cpu_port.req_ack = ddr_port.req_ack;
        end else if(cpu_port.req_valid) begin
            case( cpu_port.req_addr[23:16] )
                8'h0: begin                // UART
                    passthrough_uart_enable = 1'b1;
                    cpu_port.req_ack = passthrough_uart_req_ack;
                end
                8'h1: begin                // DDR control
                    passthrough_ddr_ctrl_enable = 1'b1;
                    cpu_port.req_ack = 1'b1;
                end
                8'h2: begin                 // GPIO
                    passthrough_gpio_enable = 1'b1;
                    cpu_port.req_ack = passthrough_gpio_req_ack;
                end
                8'h3: begin                 // Interrupt/timer controller
                    passthrough_irq_enable = 1'b1;
                    cpu_port.req_ack = passthrough_irq_req_ack;
                end
                8'h4: begin                 // SPI controller
                    passthrough_spi_enable = 1'b1;
                    cpu_port.req_ack = passthrough_spi_req_ack;
                end
                8'h5: begin                 // Display controller
                    passthrough_display_enable = 1'b1;
                    cpu_port.req_ack = passthrough_display_req_ack;
                end
                8'h6: begin                // SD
                    passthrough_sd_enable = 1'b1;
                    cpu_port.req_ack = passthrough_sd_req_ack;
                end
                8'h10: begin                // Debug logger
                    passthrough_dbglogger_enable = 1'b1;
                    cpu_port.req_ack = passthrough_dbglogger_req_ack;
                end
                default: begin
                    // Bus error case. If it's a read, it's handled with the
                    // responses. If it's a write, we have no way to
                    // communicate this to the CPU, so just do nothing.
                end
            endcase
        end
    end
end

endmodule
