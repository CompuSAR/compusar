`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/22/2022 06:24:17 PM
// Design Name:
// Module Name: top
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


module top
(
    input board_clock,
    input nReset,

    output logic[3:0] leds = 4'b1111,
    input [3:0] switches,

    output logic[3:0] debug,

    output uart_tx,
    input uart_rx,

    // SPI flash
    output                  spi_cs_n,
    inout [3:0]             spi_dq,
`ifndef SYNTHESIS
    output                  spi_clk,
`endif

    // DDR3 SDRAM
    output  wire            ddr3_reset_n,
    output  wire    [0:0]   ddr3_cke,
    output  wire    [0:0]   ddr3_ck_p,
    output  wire    [0:0]   ddr3_ck_n,
    output  wire    [0:0]   ddr3_cs_n,
    output  wire            ddr3_ras_n,
    output  wire            ddr3_cas_n,
    output  wire            ddr3_we_n,
    output  wire    [2:0]   ddr3_ba,
    output  wire    [13:0]  ddr3_addr,
    output  wire    [0:0]   ddr3_odt,
    output  wire    [1:0]   ddr3_dm,
    inout   wire    [1:0]   ddr3_dqs_p,
    inout   wire    [1:0]   ddr3_dqs_n,
    inout   wire    [15:0]  ddr3_dq,

    output wire TMDS_clk_n,
    output wire TMDS_clk_p,
    output wire[2:0] TMDS_data_n,
    output wire[2:0] TMDS_data_p,
    output wire[0:0] HDMI_OEN,

    output wire  [7:0] numeric_segments_n,
    output wire  [5:0] numeric_enable_n
);

`ifdef SYNTHESIS
localparam SIM_MODE = 0;
`else
localparam SIM_MODE = 1;
`endif

localparam CTRL_CLOCK_HZ = 75781250;
localparam BUS8_FREQ_DIV = 75;
localparam UART_BAUD = 115200;

localparam GPIO_IN_PORTS=1, GPIO_OUT_PORTS=1;

localparam GPIO_OUT0__DDR_RESET = 0;
localparam GPIO_OUT0__DISPLAY32_RESET = 1;

localparam GPIO_OUT0__6502_RESET = 16;
localparam GPIO_OUT0__FREQ_DIV_RESET = 17;
localparam GPIO_OUT0__DISPLAY8_RESET = 18;

`ifdef SYNTHESIS
wire spi_clk;
`endif

///// 32 bit section

function automatic [3:0] convert_byte_write( logic we, logic[1:0] address, logic[1:0] size );
    if( we ) begin
        logic[3:0] mask;
        case(size)
            0: mask = 4'b0001;
            1: mask = 4'b0011;
            2: mask = 4'b1111;
            3: mask = 4'b0000;
        endcase

        convert_byte_write = mask<<address;
    end else
        convert_byte_write = 4'b0;
endfunction

//-----------------------------------------------------------------
// Clocking / Reset
//-----------------------------------------------------------------
logic ctrl_cpu_clock, clocks_locked;
wire clk_w = ctrl_cpu_clock;
wire ddr_clock, ddr_ref_clock;
wire rst_w = !clocks_locked;
wire clk_ddr_dqs_w;
wire clk_ref_w;
wire clock_feedback;

wire ctrl_cpu_reset;

xpm_cdc_sync_rst reset_synchronizer(
    .dest_rst(ctrl_cpu_reset),
    .dest_clk(ctrl_cpu_clock),
    .src_rst(nReset)
);

clk_converter clocks(
    .clk_in1(board_clock), .reset(1'b0),
    .clk_ctrl_cpu(),
    .clk_ddr(ddr_clock),
    .clk_ddr_ref(ddr_ref_clock),
    .clkfb_in(clock_feedback),
    .clkfb_out(clock_feedback),
    .locked(clocks_locked)
);

localparam CACHE_PORTS_NUM = 6;
localparam CACHELINE_BITS = 128;
localparam CACHELINE_BYTES = CACHELINE_BITS/8;
localparam NUM_CACHELINES = 16*1024*8/CACHELINE_BITS;
localparam DDR_MEM_SIZE = 256*1024*1024;

localparam INST_CACHE_NUM_CACHELINES = 1024*8/CACHELINE_BITS;

logic                                   cache_port_cmd_valid_s[CACHE_PORTS_NUM];
logic [31:0]                            cache_port_cmd_addr_s[CACHE_PORTS_NUM];
logic                                   cache_port_cmd_ready_n[CACHE_PORTS_NUM];
logic [CACHELINE_BYTES-1:0]             cache_port_cmd_write_mask_s[CACHE_PORTS_NUM];
logic [CACHELINE_BITS-1:0]              cache_port_cmd_write_data_s[CACHE_PORTS_NUM];
logic                                   cache_port_rsp_valid_n[CACHE_PORTS_NUM];
logic [CACHELINE_BITS-1:0]              cache_port_rsp_read_data_n[CACHE_PORTS_NUM];

localparam CACHE_PORT_IDX_DISPLAY8 = 0;
localparam CACHE_PORT_IDX_DISPLAY32 = 1;
localparam CACHE_PORT_IDX_6502 = 2;
localparam CACHE_PORT_IDX_DBUS = 3;
localparam CACHE_PORT_IDX_IBUS = 4;
localparam CACHE_PORT_IDX_SPI_FLASH = 5;

logic                                   inst_cache_port_cmd_valid_s[0:0];
logic [31:0]                            inst_cache_port_cmd_addr_s[0:0];
logic                                   inst_cache_port_cmd_ready_n[0:0];
logic [CACHELINE_BYTES-1:0]             inst_cache_port_cmd_write_mask_s[0:0];
logic [CACHELINE_BITS-1:0]              inst_cache_port_cmd_write_data_s[0:0];
logic                                   inst_cache_port_rsp_valid_n[0:0];
logic [CACHELINE_BITS-1:0]              inst_cache_port_rsp_read_data_n[0:0];

logic           ctrl_iBus_rsp_payload_error;
logic [31:0]    ctrl_iBus_rsp_payload_inst;

logic           ctrl_dBus_cmd_valid;
logic [31:0]    ctrl_dBus_cmd_payload_address;
logic           ctrl_dBus_cmd_payload_wr;
logic [31:0]    ctrl_dBus_cmd_payload_data;
logic [1:0]     ctrl_dBus_cmd_payload_size;


logic           ctrl_dBus_cmd_ready;
logic           ctrl_dBus_rsp_valid;
logic           ctrl_dBus_rsp_error;
logic [31:0]    ctrl_dBus_rsp_data;

logic           ctrl_timer_interrupt;
logic           ctrl_ext_interrupt;
logic           ctrl_software_interrupt;
logic [31:0]    irq_lines;
localparam UART_SEND_IRQ = 0;
localparam UART_RECV_IRQ = 1;
localparam VSYNC_IRQ = 2;

logic [31:0]    iob_ddr_read_data;

VexRiscv control_cpu(
    .clk(ctrl_cpu_clock),
    .reset(!ctrl_cpu_reset || !clocks_locked),

    .timerInterrupt(ctrl_timer_interrupt),
    .externalInterrupt(ctrl_ext_interrupt),
    .softwareInterrupt(ctrl_software_interrupt),

    .iBus_cmd_ready(inst_cache_port_cmd_ready_n[0]),
    .iBus_cmd_valid(inst_cache_port_cmd_valid_s[0]),
    .iBus_cmd_payload_pc(inst_cache_port_cmd_addr_s[0]),
    .iBus_rsp_valid(inst_cache_port_rsp_valid_n[0]),
    .iBus_rsp_payload_error(ctrl_iBus_rsp_payload_error),
    .iBus_rsp_payload_inst(ctrl_iBus_rsp_payload_inst),

    .dBus_cmd_valid(ctrl_dBus_cmd_valid),
    .dBus_cmd_payload_address(ctrl_dBus_cmd_payload_address),
    .dBus_cmd_payload_wr(ctrl_dBus_cmd_payload_wr),
    .dBus_cmd_payload_data(ctrl_dBus_cmd_payload_data),
    .dBus_cmd_payload_size(ctrl_dBus_cmd_payload_size),
    .dBus_cmd_ready(ctrl_dBus_cmd_ready),
    .dBus_rsp_ready(ctrl_dBus_rsp_valid),
    .dBus_rsp_error(ctrl_dBus_rsp_error),
    .dBus_rsp_data(ctrl_dBus_rsp_data)
);

bus_width_adjust#(.OUT_WIDTH(CACHELINE_BITS)) iBus_width_adjuster(
        .clock_i(ctrl_cpu_clock),
        .in_cmd_valid_i(inst_cache_port_cmd_valid_s[0]),
        .in_cmd_addr_i(inst_cache_port_cmd_addr_s[0]),
        .in_cmd_write_mask_i(4'b0000),
        .in_cmd_write_data_i(32'h0),
        .in_rsp_read_data_o(ctrl_iBus_rsp_payload_inst),

        .out_cmd_ready_i(inst_cache_port_cmd_ready_n[0]),
        .out_cmd_write_mask_o(),
        .out_cmd_write_data_o(),
        .out_rsp_valid_i(inst_cache_port_rsp_valid_n[0]),
        .out_rsp_read_data_i(inst_cache_port_rsp_read_data_n[0])
    );
assign inst_cache_port_cmd_write_mask_s[0] = 0;

assign cache_port_cmd_addr_s[CACHE_PORT_IDX_DBUS] = ctrl_dBus_cmd_payload_address;
bus_width_adjust#(.OUT_WIDTH(CACHELINE_BITS)) dBus_width_adjuster(
        .clock_i(ctrl_cpu_clock),
        .in_cmd_valid_i(cache_port_cmd_valid_s[CACHE_PORT_IDX_DBUS]),
        .in_cmd_addr_i(ctrl_dBus_cmd_payload_address),
        .in_cmd_write_mask_i(
            convert_byte_write(
                ctrl_dBus_cmd_payload_wr,
                ctrl_dBus_cmd_payload_address[1:0],
                ctrl_dBus_cmd_payload_size
            )
        ),
        .in_cmd_write_data_i(ctrl_dBus_cmd_payload_data),
        .in_rsp_read_data_o(iob_ddr_read_data),

        .out_cmd_ready_i(ctrl_dBus_cmd_ready),
        .out_cmd_write_mask_o(cache_port_cmd_write_mask_s[CACHE_PORT_IDX_DBUS]),
        .out_cmd_write_data_o(cache_port_cmd_write_data_s[CACHE_PORT_IDX_DBUS]),
        .out_rsp_valid_i(ctrl_dBus_rsp_valid),
        .out_rsp_read_data_i(cache_port_rsp_read_data_n[CACHE_PORT_IDX_DBUS])
    );

assign ctrl_iBus_rsp_payload_error = 0;

logic ddr_ready, ddr_rsp_valid, ddr_write_data_ready;
logic ddr_ctrl_cmd_valid, ddr_ctrl_cmd_ready, ddr_ctrl_rsp_valid;
logic [31:0] ddr_ctrl_rsp_data;
logic ddr_data_cmd_valid, ddr_data_cmd_ack, ddr_cmd_write, ddr_data_rsp_valid;
logic [31:0] ddr_data_cmd_address;
logic [127:0] ddr_cmd_write_data, ddr_data_rsp_read_data;
logic irq_enable, irq_req_ack, irq_rsp_valid;
logic [31:0] irq_rsp_data;
logic spi_enable, spi_req_ack, spi_rsp_valid;
logic [31:0] spi_rsp_data;
logic gpio_enable, gpio_req_ack, gpio_rsp_valid;
logic [31:0] gpio_rsp_data;
logic uart_enable, uart_req_ack, uart_rsp_valid;
logic [31:0] uart_rsp_data;
logic display_enable, display_req_ack, display_rsp_valid;
logic [31:0] display_rsp_data;
logic apple_pager_enable, apple_pager_req_ack, apple_pager_rsp_valid;
logic [31:0] apple_pager_rsp_data;
logic ctl_apple_io_enable, ctl_apple_io_req_ack, ctl_apple_io_rsp_valid;
logic [31:0] ctl_apple_io_rsp_data;

io_block#(.CLOCK_HZ(CTRL_CLOCK_HZ)) iob(
    .clock(ctrl_cpu_clock),

    .address(ctrl_dBus_cmd_payload_address),
    .address_valid(ctrl_dBus_cmd_valid),
    .write(ctrl_dBus_cmd_payload_wr),
    .data_out(ctrl_dBus_rsp_data),

    .req_ack(ctrl_dBus_cmd_ready),
    .rsp_error(ctrl_dBus_rsp_error),
    .rsp_valid(ctrl_dBus_rsp_valid),

    .passthrough_ddr_enable(cache_port_cmd_valid_s[CACHE_PORT_IDX_DBUS]),
    .passthrough_ddr_req_ack(cache_port_cmd_ready_n[CACHE_PORT_IDX_DBUS]),
    .passthrough_ddr_rsp_valid(cache_port_rsp_valid_n[CACHE_PORT_IDX_DBUS]),
    .passthrough_ddr_data(iob_ddr_read_data),

    .passthrough_ddr_ctrl_enable(ddr_ctrl_cmd_valid),
    .passthrough_ddr_ctrl_req_ack(ddr_ctrl_cmd_ready),
    .passthrough_ddr_ctrl_rsp_valid(ddr_ctrl_rsp_valid),
    .passthrough_ddr_ctrl_data(ddr_ctrl_rsp_data),

    .passthrough_irq_enable(irq_enable),
    .passthrough_irq_req_ack(irq_req_ack),
    .passthrough_irq_rsp_data(irq_rsp_data),
    .passthrough_irq_rsp_valid(irq_rsp_valid),

    .passthrough_spi_enable(spi_enable),
    .passthrough_spi_req_ack(spi_req_ack),
    .passthrough_spi_rsp_data(spi_rsp_data),
    .passthrough_spi_rsp_valid(spi_rsp_valid),

    .passthrough_gpio_enable(gpio_enable),
    .passthrough_gpio_req_ack(gpio_req_ack),
    .passthrough_gpio_rsp_data(gpio_rsp_data),
    .passthrough_gpio_rsp_valid(gpio_rsp_valid),

    .passthrough_uart_enable(uart_enable),
    .passthrough_uart_req_ack(uart_req_ack),
    .passthrough_uart_rsp_valid(uart_rsp_valid),
    .passthrough_uart_rsp_data(uart_rsp_data),

    .passthrough_display_enable(display_enable),
    .passthrough_display_req_ack(display_req_ack),
    .passthrough_display_rsp_data(display_rsp_data),
    .passthrough_display_rsp_valid(display_rsp_valid),

    .passthrough_apple_pager_enable(apple_pager_enable),
    .passthrough_apple_pager_req_ack(apple_pager_req_ack),
    .passthrough_apple_pager_rsp_valid(apple_pager_rsp_valid),
    .passthrough_apple_pager_rsp_data(apple_pager_rsp_data),

    .passthrough_apple_io_enable(ctl_apple_io_enable),
    .passthrough_apple_io_req_ack(ctl_apple_io_req_ack),
    .passthrough_apple_io_rsp_valid(ctl_apple_io_rsp_valid),
    .passthrough_apple_io_rsp_data(ctl_apple_io_rsp_data)

);

cache#(
    .CACHELINE_BITS(CACHELINE_BITS),
    .NUM_CACHELINES(INST_CACHE_NUM_CACHELINES),
    .BACKEND_SIZE_BYTES(DDR_MEM_SIZE),
    .NUM_PORTS(1)
) inst_cache(
    .clock_i(ctrl_cpu_clock),

    .ctrl_cmd_addr_i(),
    .ctrl_cmd_valid_i(),
    .ctrl_cmd_ready_o(),
    .ctrl_cmd_write_i(),
    .ctrl_cmd_data_i(),
    .ctrl_rsp_valid_o(),
    .ctrl_rsp_data_o(),

    .port_cmd_valid_i(inst_cache_port_cmd_valid_s),
    .port_cmd_addr_i(inst_cache_port_cmd_addr_s),
    .port_cmd_ready_o(inst_cache_port_cmd_ready_n),
    .port_cmd_write_mask_i(inst_cache_port_cmd_write_mask_s),
    .port_cmd_write_data_i(inst_cache_port_cmd_write_data_s),
    .port_rsp_valid_o(inst_cache_port_rsp_valid_n),
    .port_rsp_read_data_o(inst_cache_port_rsp_read_data_n),

    .backend_cmd_valid_o(cache_port_cmd_valid_s[CACHE_PORT_IDX_IBUS]),
    .backend_cmd_addr_o(cache_port_cmd_addr_s[CACHE_PORT_IDX_IBUS]),
    .backend_cmd_ready_i(cache_port_cmd_ready_n[CACHE_PORT_IDX_IBUS]),
    .backend_cmd_write_o(),
    .backend_cmd_write_data_o(),
    .backend_rsp_valid_i(cache_port_rsp_valid_n[CACHE_PORT_IDX_IBUS]),
    .backend_rsp_read_data_i(cache_port_rsp_read_data_n[CACHE_PORT_IDX_IBUS])
);

assign cache_port_cmd_write_mask_s[CACHE_PORT_IDX_IBUS] = { CACHELINE_BYTES{1'b0} };

cache#(
    .CACHELINE_BITS(CACHELINE_BITS),
    .NUM_CACHELINES(NUM_CACHELINES),
    .BACKEND_SIZE_BYTES(DDR_MEM_SIZE),
    .INIT_FILE("boot_loader.mem"),
    .STATE_INIT("boot_loader_state.mem"),
    .NUM_PORTS(CACHE_PORTS_NUM)
) cache(
    .clock_i(ctrl_cpu_clock),

    .ctrl_cmd_addr_i(),
    .ctrl_cmd_valid_i(),
    .ctrl_cmd_ready_o(),
    .ctrl_cmd_write_i(),
    .ctrl_cmd_data_i(),
    .ctrl_rsp_valid_o(),
    .ctrl_rsp_data_o(),

    .port_cmd_valid_i(cache_port_cmd_valid_s),
    .port_cmd_addr_i(cache_port_cmd_addr_s),
    .port_cmd_ready_o(cache_port_cmd_ready_n),
    .port_cmd_write_mask_i(cache_port_cmd_write_mask_s),
    .port_cmd_write_data_i(cache_port_cmd_write_data_s),
    .port_rsp_valid_o(cache_port_rsp_valid_n),
    .port_rsp_read_data_o(cache_port_rsp_read_data_n),

    .backend_cmd_valid_o(ddr_data_cmd_valid),
    .backend_cmd_addr_o(ddr_data_cmd_address),
    .backend_cmd_ready_i(ddr_data_cmd_ack),
    .backend_cmd_write_o(ddr_data_cmd_write),
    .backend_cmd_write_data_o(ddr_cmd_write_data),
    .backend_rsp_valid_i(ddr_data_rsp_valid),
    .backend_rsp_read_data_i(ddr_data_rsp_read_data)
);

display display_ctrl(
    .raw_clock_i(board_clock),
    .ctrl_clock_i(ctrl_cpu_clock),
    .reset32_i(gp_out[0][GPIO_OUT0__DISPLAY32_RESET]),
    .reset8_i(gp_out[0][GPIO_OUT0__DISPLAY8_RESET]),
    .vsync_irq_o(irq_lines[VSYNC_IRQ]),

    .ctrl_req_valid_i(display_enable),
    .ctrl_req_ack_o(display_req_ack),
    .ctrl_req_addr_i(ctrl_dBus_cmd_payload_address[15:0]),
    .ctrl_req_data_i(ctrl_dBus_cmd_payload_data),
    .ctrl_req_write_i(ctrl_dBus_cmd_payload_wr),
    .ctrl_rsp_valid_o(display_rsp_valid),
    .ctrl_rsp_data_o(display_rsp_data),

    .dma32_req_valid_o(cache_port_cmd_valid_s[CACHE_PORT_IDX_DISPLAY32]),
    .dma32_req_write_mask_o(cache_port_cmd_write_mask_s[CACHE_PORT_IDX_DISPLAY32]),
    .dma32_req_addr_o(cache_port_cmd_addr_s[CACHE_PORT_IDX_DISPLAY32]),
    .dma32_req_ack_i(cache_port_cmd_ready_n[CACHE_PORT_IDX_DISPLAY32]),
    .dma32_rsp_valid_i(cache_port_rsp_valid_n[CACHE_PORT_IDX_DISPLAY32]),
    .dma32_rsp_data_i(cache_port_rsp_read_data_n[CACHE_PORT_IDX_DISPLAY32]),

    //.dma8_req_valid_o(cache_port_cmd_valid_s[CACHE_PORT_IDX_DISPLAY8]),
    //.dma8_req_write_mask_o(cache_port_cmd_write_mask_s[CACHE_PORT_IDX_DISPLAY8]),
    //.dma8_req_addr_o(cache_port_cmd_addr_s[CACHE_PORT_IDX_DISPLAY8]),
    .dma8_req_ack_i(cache_port_cmd_ready_n[CACHE_PORT_IDX_DISPLAY8]),
    .dma8_rsp_valid_i(cache_port_rsp_valid_n[CACHE_PORT_IDX_DISPLAY8]),
    .dma8_rsp_data_i(cache_port_rsp_read_data_n[CACHE_PORT_IDX_DISPLAY8]),

    .TMDS_clk_n,
    .TMDS_clk_p,
    .TMDS_data_n,
    .TMDS_data_p,
    .HDMI_OEN
);

//-----------------------------------------------------------------
// DDR Core + PHY
//-----------------------------------------------------------------
wire ddr_reset_n;
wire ddr_phy_reset_n;

wire ddr_phy_cke;
wire ddr_phy_odt;
wire ddr_phy_ras_n;
wire ddr_phy_cas_n;
wire ddr_phy_we_n;

wire ddr_phy_cs_n;
wire [2:0] ddr_phy_ba;
wire [13:0] ddr_phy_addr;
wire [1:0] ddr_phy_dqs_i, ddr_phy_dqs_o;
wire ddr_phy_data_transfer, ddr_phy_data_write, ddr_phy_write_level, ddr_phy_dqs_out;
wire [15:0] ddr_phy_dq_i[7:0], ddr_phy_dq_o[1:0];
wire [31:0] ddr_phy_delay_inc;

wire ddr_actual_enable, ddr_actual_ready, ddr_actual_data_ready;
logic [127:0]ddr_actual_write_data;
logic ddr_actual_data_valid = 1'b0;

assign ddr_data_cmd_ack = ddr_actual_ready && !ddr_actual_data_valid;
assign ddr_actual_enable = ddr_data_cmd_valid && !ddr_actual_data_valid;

always_ff@(posedge ctrl_cpu_clock) begin
    if( ddr_data_cmd_valid && ddr_data_cmd_write && ddr_actual_ready && !ddr_actual_data_valid ) begin
        ddr_actual_write_data <= ddr_cmd_write_data;
        ddr_actual_data_valid <= 1'b1;
    end
    if( ddr_actual_data_valid && ddr_actual_data_ready ) begin
        ddr_actual_data_valid <= 1'b0;
    end
end

assign ddr3_dm = 2'b00;

mig_ddr_ctrl ddr_ctrl(
    .ui_clk( ctrl_cpu_clock ),
    .sys_clk_i( ddr_clock ),
    .clk_ref_i( ddr_ref_clock ),
    .sys_rst( 1'b0 ),

    .app_en( ddr_actual_enable ),
    .app_rdy( ddr_actual_ready ),
    .app_cmd( ddr_data_cmd_write ? 3'b000 : 3'b001 ),
    .app_addr( ddr_data_cmd_address[27:0] ),

    .app_wdf_data( ddr_actual_write_data ),
    .app_wdf_rdy( ddr_actual_data_ready ),
    .app_wdf_end( 1'b1 ),
    .app_wdf_wren( ddr_actual_data_valid ),

    .app_rd_data_valid( ddr_data_rsp_valid ),
    .app_rd_data( ddr_data_rsp_read_data ),

    .app_ref_req( 1'b0 ),
    .app_zq_req( 1'b0 ),
    .app_sr_req( 1'b0 ),

    // DDR side
    .ddr3_dq( ddr3_dq ),
    .ddr3_dqs_n( ddr3_dqs_n ),
    .ddr3_dqs_p( ddr3_dqs_p ),
    .ddr3_addr( ddr3_addr ),
    .ddr3_ba( ddr3_ba ),
    .ddr3_cas_n( ddr3_cas_n ),
    .ddr3_ck_n( ddr3_ck_n ),
    .ddr3_ck_p( ddr3_ck_p ),
    .ddr3_cke( ddr3_cke ),
    .ddr3_cs_n( ddr3_cs_n ),
    .ddr3_odt( ddr3_odt ),
    .ddr3_ras_n( ddr3_ras_n ),
    .ddr3_reset_n( ddr3_reset_n ),
    .ddr3_we_n( ddr3_we_n )
);


timer_int_ctrl#(.CLOCK_HZ(CTRL_CLOCK_HZ)) interrupt_controller(
    .clock(ctrl_cpu_clock),
    .req_addr_i(ctrl_dBus_cmd_payload_address[15:0]),
    .req_data_i(ctrl_dBus_cmd_payload_data),
    .req_write_i(ctrl_dBus_cmd_payload_wr),
    .req_valid_i(irq_enable),
    .req_ready_o(irq_req_ack),

    .rsp_data_o(irq_rsp_data),
    .rsp_valid_o(irq_rsp_valid),

    .irqs_i(irq_lines),

    .ctrl_timer_interrupt_o(ctrl_timer_interrupt),
    .ctrl_ext_interrupt_o(ctrl_ext_interrupt),
    .ctrl_software_interrupt_i(ctrl_software_interrupt)
);

wire [3:0]buffered_switches;

input_delay#(.NUM_BITS(4)) switches_delay(
    .clock_i(ctrl_cpu_clock),
    .in(switches),
    .out(buffered_switches)
);

wire [31:0]gp_out[GPIO_OUT_PORTS];

gpio#(
    .NUM_IN_PORTS(GPIO_IN_PORTS),
    .NUM_OUT_PORTS(GPIO_OUT_PORTS))
gpio(
    .clock_i(ctrl_cpu_clock),
    .req_addr_i(ctrl_dBus_cmd_payload_address[15:0]),
    .req_data_i(ctrl_dBus_cmd_payload_data),
    .req_write_i(ctrl_dBus_cmd_payload_wr),
    .req_valid_i(gpio_enable),
    .req_ready_o(gpio_req_ack),

    .rsp_data_o(gpio_rsp_data),
    .rsp_valid_o(gpio_rsp_valid),

    .gp_in( '{ {28'b0, buffered_switches} } ),
    .gp_out( gp_out )
);

wire spi_flash_dma_write;
spi_ctrl#(.MEM_DATA_WIDTH(CACHELINE_BITS)) spi_flash(
    .cpu_clock_i(ctrl_cpu_clock),
    .spi_ref_clock_i(board_clock),
    .irq(),

 //   .debug(debug),

    .ctrl_cmd_valid_i(spi_enable),
    .ctrl_cmd_address_i(ctrl_dBus_cmd_payload_address[15:0]),
    .ctrl_cmd_data_i(ctrl_dBus_cmd_payload_data),
    .ctrl_cmd_write_i(ctrl_dBus_cmd_payload_wr),
    .ctrl_cmd_ack_o(spi_req_ack),

    .ctrl_rsp_valid_o(spi_rsp_valid),
    .ctrl_rsp_data_o(spi_rsp_data),

    .spi_cs_n_o(spi_cs_n),
    .spi_dq_io(spi_dq),
    .spi_clk_o(spi_clk),

    .dma_cmd_valid_o(cache_port_cmd_valid_s[CACHE_PORT_IDX_SPI_FLASH]),
    .dma_cmd_address_o(cache_port_cmd_addr_s[CACHE_PORT_IDX_SPI_FLASH]),
    .dma_cmd_data_o(cache_port_cmd_write_data_s[CACHE_PORT_IDX_SPI_FLASH]),
    .dma_cmd_write_o(spi_flash_dma_write),
    .dma_cmd_ack_i(cache_port_cmd_ready_n[CACHE_PORT_IDX_SPI_FLASH]),

    .dma_rsp_valid_i(cache_port_rsp_valid_n[CACHE_PORT_IDX_SPI_FLASH]),
    .dma_rsp_data_i(cache_port_rsp_read_data_n[CACHE_PORT_IDX_SPI_FLASH])
);

uart_ctrl#(.ClockDivider(SIM_MODE ? 10 : CTRL_CLOCK_HZ / UART_BAUD), .SimMode(SIM_MODE)) uart_ctrl(
    .clock( ctrl_cpu_clock ),

    .req_valid_i(uart_enable),
    .req_addr_i(ctrl_dBus_cmd_payload_address[15:0]),
    .req_data_i(ctrl_dBus_cmd_payload_data),
    .req_write_i(ctrl_dBus_cmd_payload_wr),
    .req_ack_o(uart_req_ack),

    .rsp_valid_o(uart_rsp_valid),
    .rsp_data_o(uart_rsp_data),

    .intr_send_ready_o(irq_lines[UART_SEND_IRQ]),
    .intr_recv_ready_o(irq_lines[UART_RECV_IRQ]),

    .uart_tx(uart_tx),
    .uart_rx(uart_rx)
);

STARTUPE2 startup_cfg(
    .GSR(1'b0),
    .GTS(1'b0),
    .KEYCLEARB(1'b0),
    .PACK(1'b0),
    .PREQ(),
    .USRCCLKO(spi_clk),
    .USRCCLKTS(spi_cs_n),
    .USRDONEO(1'b1),
    .USRDONETS(1'b1)
);

genvar i;
generate
    for(i=3; i<32; ++i)
        assign irq_lines[i] = 1'b0;
endgenerate

generate
    for(i=0; i<CACHELINE_BYTES; ++i)
        assign cache_port_cmd_write_mask_s[CACHE_PORT_IDX_SPI_FLASH][i] = spi_flash_dma_write;
endgenerate

always_ff@(posedge ctrl_cpu_clock) begin
    leds[1] <= gp_out[0][GPIO_OUT0__6502_RESET];
end

int blink_counter = 0;
always_ff@(posedge board_clock) begin
    blink_counter <= blink_counter-1;

    if( blink_counter == 0 ) begin
        leds[3] <= !leds[3];
        blink_counter <= 50000000;
    end
end

wire bus8_req_valid, bus8_mem_req_valid, bus8_req_ack, bus8_rsp_valid, bus8_mem_rsp_valid;
wire apple_io_req_ack;
wire bus8_req_write, bus8_mem_req_write;
wire [7:0] bus8_req_data, bus8_mem_req_data, bus8_rsp_data, bus8_mem_rsp_data;
wire [15:0] bus8_req_addr, bus8_mem_req_addr;
wire [31:0] bus8_paged_req_addr;

bus_width_adjust#(.IN_WIDTH(8), .OUT_WIDTH(CACHELINE_BITS), .ADDR_WIDTH(32)) bus8_width_adjuster(
    .clock_i( ctrl_cpu_clock ),
    .in_cmd_valid_i( cache_port_cmd_valid_s[CACHE_PORT_IDX_6502] ),
    .in_cmd_addr_i( bus8_paged_req_addr ),
    .in_cmd_write_mask_i( bus8_mem_req_write ),
    .in_cmd_write_data_i( bus8_mem_req_data ),
    .in_rsp_read_data_o( bus8_mem_rsp_data ),

    .out_cmd_ready_i( bus8_mem_req_ack ),
    .out_cmd_write_mask_o( cache_port_cmd_write_mask_s[CACHE_PORT_IDX_6502] ),
    .out_cmd_write_data_o( cache_port_cmd_write_data_s[CACHE_PORT_IDX_6502] ),
    .out_rsp_valid_i( cache_port_rsp_valid_n[CACHE_PORT_IDX_6502] ),
    .out_rsp_read_data_i( cache_port_rsp_read_data_n[CACHE_PORT_IDX_6502] )
);

freq_div_bus#() freq_div_6502(
    .clock_i( ctrl_cpu_clock ),
    .ctl_div_nom_i( BUS8_FREQ_DIV ),
    .ctl_div_denom_i( 16'd1 ),
    .reset_i( gp_out[0][GPIO_OUT0__FREQ_DIV_RESET] ),

    .slow_cmd_valid_i( bus8_req_valid ),
    .slow_cmd_ready_o( bus8_req_ack ),

    .fast_cmd_valid_o( bus8_mem_req_valid ),
    .fast_cmd_ready_i( apple_io_req_ack )
    );

wire apple_cpu_sync, apple_cpu_vector_pull, apple_cpu_memory_lock;
sar6502_sync apple_cpu(
    .clock_i( ctrl_cpu_clock ),

    .reset_i( gp_out[0][GPIO_OUT0__6502_RESET] ),
    .nmi_i( 1'b0 ),
    .irq_i( 1'b0 ),
    .set_overflow_i( 1'b0 ),

    .bus_req_valid_o( bus8_req_valid ),
    .bus_req_address_o( bus8_req_addr ),
    .bus_req_write_o( bus8_req_write ),
    .bus_req_ack_i( bus8_req_ack ),
    .bus_req_data_o( bus8_req_data ),
    .bus_rsp_valid_i( bus8_rsp_valid ),
    .bus_rsp_data_i( bus8_rsp_data ),

    .sync_o( apple_cpu_sync ),
    .vector_pull_o( apple_cpu_vector_pull ),
    .memory_lock_o( apple_cpu_memory_lock )
);

apple_io apple_io_block(
    .clock_i( ctrl_cpu_clock ),

    .cpu_req_valid_i( bus8_mem_req_valid ),
    .cpu_req_ack_o( apple_io_req_ack ),
    .cpu_req_write_i( bus8_req_write ),
    .cpu_req_addr_i( bus8_req_addr ),
    .cpu_req_data_i( bus8_req_data ),

    .cpu_rsp_valid_o( bus8_rsp_valid ),
    .cpu_rsp_data_o( bus8_rsp_data ),

    .mem_req_valid_o( cache_port_cmd_valid_s[CACHE_PORT_IDX_6502] ),
    .mem_req_ack_i( cache_port_cmd_ready_n[CACHE_PORT_IDX_6502] ),
    .mem_req_write_o( bus8_mem_req_write ),
    .mem_req_data_o( bus8_mem_req_data ),
    .mem_req_addr_o( bus8_mem_req_addr ),

    .mem_rsp_valid_i( cache_port_rsp_valid_n[CACHE_PORT_IDX_6502] ),
    .mem_rsp_data_i( bus8_mem_rsp_data ),

    .ctrl_req_valid_i( ctl_apple_io_enable ),
    .ctrl_req_write_i( ctrl_dBus_cmd_payload_wr ),
    .ctrl_req_addr_i( ctrl_dBus_cmd_payload_address[15:0] ),
    .ctrl_req_data_i( ctrl_dBus_cmd_payload_data ),
    .ctrl_req_ack_o( ctl_apple_io_req_ack ),
    .ctrl_rsp_valid_o( ctl_apple_io_rsp_valid ),
    .ctrl_rsp_data_o( ctl_apple_io_rsp_data ),

    .ctrl_intr_o( ctrl_software_interrupt )
);

apple_pager pager(
    .clock_i( ctrl_cpu_clock ),

    .cpu_req_valid_i( cache_port_cmd_valid_s[CACHE_PORT_IDX_6502] ),
    .cpu_req_write_i( bus8_mem_req_write ),
    .cpu_req_addr_i( bus8_mem_req_addr ),

    .mem_req_addr_o( bus8_paged_req_addr ),

    .ctrl_req_valid_i( apple_pager_enable ),
    .ctrl_req_write_i( ctrl_dBus_cmd_payload_wr ),
    .ctrl_req_addr_i( ctrl_dBus_cmd_payload_address[15:0] ),
    .ctrl_req_data_i( ctrl_dBus_cmd_payload_data ),
    .ctrl_req_ack_o( apple_pager_req_ack ),
    .ctrl_rsp_valid_o( apple_pager_rsp_valid ),
    .ctrl_rsp_data_o( apple_pager_rsp_data )

);

assign cache_port_cmd_addr_s[CACHE_PORT_IDX_6502] = bus8_paged_req_addr;

assign cache_port_cmd_write_mask_s[CACHE_PORT_IDX_DISPLAY8] = { CACHELINE_BYTES{1'b0} };
display_serial#(.CLOCK_SPEED(CTRL_CLOCK_HZ), .TEXT_PAGE_ADDR(32'h81010400))
apple_display(
    .clock_i(ctrl_cpu_clock),
    .reset_i(gp_out[0][GPIO_OUT0__DISPLAY8_RESET]),

    .req_valid_o(cache_port_cmd_valid_s[CACHE_PORT_IDX_DISPLAY8]),
    .req_addr_o(cache_port_cmd_addr_s[CACHE_PORT_IDX_DISPLAY8]),
    .req_ack_i(cache_port_cmd_ready_n[CACHE_PORT_IDX_DISPLAY8]),
    .rsp_valid_i(cache_port_rsp_valid_n[CACHE_PORT_IDX_DISPLAY8]),
    .rsp_data_i(cache_port_rsp_read_data_n[CACHE_PORT_IDX_DISPLAY8]),

    .uart_send_o(/*uart_tx*/ debug[0])
);

logic[4*6-1:0] debug_display_data = 24'hffffff;
logic[5:0] debug_display_point = 6'b000000;

seg_display#(.FREQ_DIV(10000), .NUM_DIGITS(6), .SEG_ACTIVE_LOW(1)) debug_display(
    .clock_i(ctrl_cpu_clock),
    .data_i(debug_display_data),
    .point_i(debug_display_point),
    .segments_o(numeric_segments_n),
    .enable_o(numeric_enable_n)
);

logic debug_pending_req = 1'b0;
always_ff@(posedge ctrl_cpu_clock) begin
    if( bus8_req_valid && !bus8_req_write && apple_cpu_sync ) begin
        debug_display_data[15:0] <= bus8_req_addr;
        debug_pending_req <= 1'b1;
    end

    if( debug_pending_req == 1'b1 && bus8_rsp_valid ) begin
        debug_display_data[23:16] = bus8_rsp_data;
        debug_pending_req <= 1'b0;
    end

    if( bus8_req_valid && bus8_req_ack ) begin
        debug_display_point <= debug_display_point + 1;
    end
end

endmodule
