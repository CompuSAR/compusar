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


module io_block#(
    parameter CLOCK_HZ = 50000000
)
(
    input clock,

    input [31:0] address,
    input address_valid,
    input write,
    output logic [31:0] data_out,
    output logic req_ack,
    output logic rsp_error,
    output logic rsp_valid,

    output logic passthrough_ddr_enable,
    input passthrough_ddr_req_ack,
    input passthrough_ddr_rsp_valid,
    input [31:0] passthrough_ddr_data,

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

    output logic passthrough_apple_pager_enable,
    input passthrough_apple_pager_req_ack,
    input passthrough_apple_pager_rsp_valid,
    input [31:0] passthrough_apple_pager_rsp_data,

    output logic passthrough_apple_io_enable,
    input passthrough_apple_io_req_ack,
    input passthrough_apple_io_rsp_valid,
    input [31:0] passthrough_apple_io_rsp_data

    );

logic [31:0] previous_address, previous_address_next;
logic previous_valid=1'b0;

always_ff@(posedge clock) begin
    previous_address <= previous_address_next;

    if( previous_valid && !rsp_valid )
        // Previous cycle still waiting for response. Don't advance.
        previous_valid <= 1'b1;
    else if( address_valid && req_ack )
        previous_valid = !write;
    else
        previous_valid = 1'b0;
end

logic uart_send_data_ready;
logic uart_recv_ready;

task default_state_current();
    uart_send_data_ready = 1'b0;
    req_ack = 1'b1;
    previous_address_next = address;

    passthrough_uart_enable = 1'b0;
    passthrough_ddr_enable = 1'b0;
    passthrough_ddr_ctrl_enable = 1'b0;
    passthrough_gpio_enable = 1'b0;
    passthrough_irq_enable = 1'b0;
    passthrough_spi_enable = 1'b0;
    passthrough_apple_pager_enable = 1'b0;
    passthrough_apple_io_enable = 1'b0;
endtask

function logic is_ddr(logic [31:0]address);
    is_ddr = address[31:30] == 2'b10;
endfunction

function logic is_io(logic [31:0]address);
    is_io = address[31:30] == 2'b11;
endfunction

always_comb begin
    // Previous cycle analysis
    rsp_valid = 1'bX;
    rsp_error = 1'b0;
    data_out = 32'bX;

    if( previous_valid ) begin
        if( is_ddr(previous_address) ) begin
            data_out = passthrough_ddr_data;
            rsp_valid = passthrough_ddr_rsp_valid;
        end else begin
            case( previous_address[23:16] )
                8'h0: begin                     // UART
                    rsp_valid = passthrough_uart_rsp_valid;
                    data_out = passthrough_uart_rsp_data;
                end
                8'h1: begin                     // DDR control
                    rsp_valid = passthrough_ddr_ctrl_rsp_valid;
                    data_out = passthrough_ddr_ctrl_data;
                end
                8'h2: begin                     // GPIO
                    rsp_valid = passthrough_gpio_rsp_valid;
                    data_out = passthrough_gpio_rsp_data;
                end
                8'h3: begin                     // Interrupt controller
                    rsp_valid = passthrough_irq_rsp_valid;
                    data_out = passthrough_irq_rsp_data;
                end
                8'h4: begin                     // SPI controller
                    rsp_valid = passthrough_spi_rsp_valid;
                    data_out = passthrough_spi_rsp_data;
                end
                8'h5: begin                     // Apple II pager
                    rsp_valid = passthrough_apple_pager_rsp_valid;
                    data_out = passthrough_apple_pager_rsp_data;
                end
                8'h6: begin                     // Apple II IO
                    rsp_valid = passthrough_apple_io_rsp_valid;
                    data_out = passthrough_apple_io_rsp_data;
                end
                default: begin                  // Invalid memory access
                    rsp_valid = 1'b1;
                    rsp_error = 1'b1;
                end
            endcase
        end
    end
end

always_comb begin
    default_state_current();

    // Current cycle analysis
    if( previous_valid && !rsp_valid ) begin
        // Previous cycle still waiting for response. Don't advance.
        previous_address_next = previous_address;
        req_ack = 1'b0;
    end else begin
        if( is_ddr(address) ) begin
            passthrough_ddr_enable = address_valid;
            req_ack = passthrough_ddr_req_ack;
        end else if(address_valid) begin
            case( address[23:16] )
                8'h0: begin                // UART
                    passthrough_uart_enable = 1'b1;
                    req_ack = passthrough_uart_req_ack;
                end
                8'h1: begin                // DDR control
                    passthrough_ddr_ctrl_enable = 1'b1;
                    req_ack = 1'b1;
                end
                8'h2: begin                 // GPIO
                    passthrough_gpio_enable = 1'b1;
                    req_ack = passthrough_gpio_req_ack;
                end
                8'h3: begin                 // Interrupt/timer controller
                    passthrough_irq_enable = 1'b1;
                    req_ack = passthrough_irq_req_ack;
                end
                8'h4: begin                 // SPI controller
                    passthrough_spi_enable = 1'b1;
                    req_ack = passthrough_spi_req_ack;
                end
                8'h5: begin                // Apple II pager
                    passthrough_apple_pager_enable = 1'b1;
                    req_ack = passthrough_apple_pager_req_ack;
                end
                8'h6: begin                // Apple II io
                    passthrough_apple_io_enable = 1'b1;
                    req_ack = passthrough_apple_io_req_ack;
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
