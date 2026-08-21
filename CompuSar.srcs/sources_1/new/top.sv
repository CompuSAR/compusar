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
    output logic[3:0] debug2,

    output uart_tx,
    input uart_rx,

    // SPI flash
    output                  spi_cs_n,
    inout [3:0]             spi_dq,
`ifndef SYNTHESIS
    output                  spi_clk,
`endif

    // SD card
    inout                   sd_cmd,
    inout [3:0]             sd_data,
    output                  sd_clk,
    input                   sd_card_detect_n,

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
localparam GPIO_OUT0__DISPLAY8_RESET = 2;
localparam GPIO_OUT0__SD_CARD_POLARITY = 3;

localparam GPIO_OUT0__6502_RESET = 16;
localparam GPIO_OUT0__FREQ_DIV_RESET = 17;
localparam GPIO_OUT0__A2_DISK_CTRL_RESET = 18;

`ifdef SYNTHESIS
wire spi_clk;
`endif

///// 32 bit section

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

logic bus_clock_25, bus_clock_50, bus_clock_200, bus_clock_feedback;

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

bus_clocks bus_clocks(
    .clk_in1(board_clock),
    .clkfb_in(bus_clock_feedback),

    .clk_25(bus_clock_25),
    .clk_50(bus_clock_50),
    .clk_200(bus_clock_200),
    .clkfb_out(bus_clock_feedback)
);

localparam CACHE_PORTS_NUM = 8;
localparam CACHELINE_BITS = 128;
localparam CACHELINE_BYTES = CACHELINE_BITS/8;
localparam NUM_CACHELINES = 16*1024*8/CACHELINE_BITS;
localparam DDR_MEM_SIZE = 256*1024*1024;
localparam DMA_WRITE_ALL_SET = { CACHELINE_BYTES{1'b1} };
localparam DMA_WRITE_ALL_CLEAR = { CACHELINE_BYTES{1'b0} };

localparam INST_CACHE_NUM_CACHELINES = 1024*8/CACHELINE_BITS;

sync_bus_write_mask#(.DATA_WIDTH(CACHELINE_BITS), .ADDR_WIDTH(32)) cache_ports[CACHE_PORTS_NUM]();

localparam CACHE_PORT_IDX_DISPLAY8 = 0;
localparam CACHE_PORT_IDX_DISPLAY32 = 1;
localparam CACHE_PORT_IDX_SD = 2;
localparam CACHE_PORT_IDX_6502 = 3;
localparam CACHE_PORT_IDX_DBUS = 4;
localparam CACHE_PORT_IDX_IBUS = 5;
localparam CACHE_PORT_IDX_SPI_FLASH = 6;
localparam CACHE_PORT_IDX_APPLE_DISK = 7;

sync_bus_write_mask#(.DATA_WIDTH(CACHELINE_BITS), .ADDR_WIDTH(32)) inst_cache_ports[1]();

sync_bus_write_mask ctrl_dbus(), ctrl_ddr_bus(), ctrl_ibus();

logic           ctrl_iBus_rsp_payload_error;

logic           ctrl_dBus_cmd_payload_wr;
logic [3:0]     ctrl_dBus_cmd_payload_mask;
logic [1:0]     ctrl_dBus_cmd_payload_size;


logic           ctrl_dBus_rsp_error;

logic           ctrl_timer_interrupt;
logic           ctrl_ext_interrupt;
logic           ctrl_software_interrupt;
logic [31:0]    irq_lines;
localparam UART_SEND_IRQ = 0;
localparam UART_RECV_IRQ = 1;
localparam VSYNC_IRQ = 2;
localparam SD_INSERT_IRQ = 3;
localparam SD_DATA_IDLE = 4;
localparam FIRST_EMPTY_BASE_IRQ = 5;
localparam DBG_6502_IRQ = 16;
localparam FIRST_EMPTY_AUX_IRQ = 17;

wire [31:0] gp_out[GPIO_OUT_PORTS];

VexRiscv control_cpu(
    .clk(ctrl_cpu_clock),
    .reset(!ctrl_cpu_reset || !clocks_locked),

    .timerInterrupt(ctrl_timer_interrupt),
    .externalInterrupt(ctrl_ext_interrupt),
    .softwareInterrupt(ctrl_software_interrupt),

    .iBus_cmd_ready(ctrl_ibus.req_ack),
    .iBus_cmd_valid(ctrl_ibus.req_valid),
    .iBus_cmd_payload_pc(ctrl_ibus.req_addr),
    .iBus_rsp_valid(ctrl_ibus.rsp_valid),
    .iBus_rsp_payload_error(ctrl_iBus_rsp_payload_error),
    .iBus_rsp_payload_inst(ctrl_ibus.rsp_data),

    .dBus_cmd_valid(ctrl_dbus.req_valid),
    .dBus_cmd_payload_address(ctrl_dbus.req_addr),
    .dBus_cmd_payload_wr(ctrl_dBus_cmd_payload_wr),
    .dBus_cmd_payload_mask(ctrl_dBus_cmd_payload_mask),
    .dBus_cmd_payload_data(ctrl_dbus.req_data),
    .dBus_cmd_payload_size(ctrl_dBus_cmd_payload_size),
    .dBus_cmd_ready(ctrl_dbus.req_ack),
    .dBus_rsp_ready(ctrl_dbus.rsp_valid),
    .dBus_rsp_error(ctrl_dBus_rsp_error),
    .dBus_rsp_data(ctrl_dbus.rsp_data)
);

assign ctrl_dbus.req_write_mask = ctrl_dBus_cmd_payload_wr ? ctrl_dBus_cmd_payload_mask : 4'b0000;

assign ctrl_ibus.req_write_mask = 4'b0000;

bus_width_adjust iBus_width_adjuster(
        .clock_i(ctrl_cpu_clock),

        .north_port(ctrl_ibus),
        .south_port(inst_cache_ports[0])
    );

bus_width_adjust dBus_width_adjuster(
        .clock_i(ctrl_cpu_clock),

        .north_port(ctrl_ddr_bus),
        .south_port(cache_ports[CACHE_PORT_IDX_DBUS])
    );

assign ctrl_iBus_rsp_payload_error = 0;

enum {
    IO_PORT_UART,
    IO_PORT_DDR_CTRL,
    IO_PORT_GPIO,
    IO_PORT_INT,
    IO_PORT_SPI,
    IO_PORT_DISPLAY,
    IO_PORT_SD,
    IO_PORT_DBG_LOGGER,

    IO_PORT_APPLE_PAGER,
    IO_PORT_APPLE_IO,
    IO_PORT_APPLE_DISKETTE,
    IO_PORT_6502_DEBUGGER,

    IOPORT_NUM_PORTS
} IO_PORTS_ASSIGNMENTS;

sync_bus#(.ADDR_WIDTH(16)) io_ports_bus[IOPORT_NUM_PORTS]();

assign io_ports_bus[IO_PORT_DDR_CTRL].req_ack = 1'b0;   // DDR controller is currently unused
assign io_ports_bus[IO_PORT_DDR_CTRL].rsp_valid = 1'b0;

logic ddr_data_cmd_valid, ddr_data_cmd_ack, ddr_cmd_write, ddr_data_rsp_valid;
logic [127:0] ddr_cmd_write_data, ddr_data_rsp_read_data;
logic [31:0] ddr_data_cmd_address;

io_block#(
    .NUM_PORTS(IOPORT_NUM_PORTS),
    .FIRST_AUX_PORT(IO_PORT_APPLE_PAGER)
) iob(
    .clock(ctrl_cpu_clock),

    .cpu_port(ctrl_dbus),
    .rsp_error(ctrl_dBus_rsp_error),

    .ddr_port(ctrl_ddr_bus),
    .ports(io_ports_bus)
);

cache#(
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

    .ports(inst_cache_ports),

    .backend_cmd_valid_o(cache_ports[CACHE_PORT_IDX_IBUS].req_valid),
    .backend_cmd_addr_o(cache_ports[CACHE_PORT_IDX_IBUS].req_addr),
    .backend_cmd_ready_i(cache_ports[CACHE_PORT_IDX_IBUS].req_ack),
    .backend_cmd_write_o(),
    .backend_cmd_write_data_o(),
    .backend_rsp_valid_i(cache_ports[CACHE_PORT_IDX_IBUS].rsp_valid),
    .backend_rsp_read_data_i(cache_ports[CACHE_PORT_IDX_IBUS].rsp_data)
);

assign cache_ports[CACHE_PORT_IDX_IBUS].req_write_mask = DMA_WRITE_ALL_CLEAR;

cache#(
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

    .ports(cache_ports),

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

    .ctrl(io_ports_bus[IO_PORT_DISPLAY]),

    .dma32(cache_ports[CACHE_PORT_IDX_DISPLAY32]),
    .dma8(cache_ports[CACHE_PORT_IDX_DISPLAY8]),

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

    .req_addr_i(io_ports_bus[IO_PORT_INT].req_addr),
    .req_data_i(io_ports_bus[IO_PORT_INT].req_data),
    .req_write_i(io_ports_bus[IO_PORT_INT].req_write),
    .req_valid_i(io_ports_bus[IO_PORT_INT].req_valid),
    .req_ready_o(io_ports_bus[IO_PORT_INT].req_ack),

    .rsp_data_o(io_ports_bus[IO_PORT_INT].rsp_data),
    .rsp_valid_o(io_ports_bus[IO_PORT_INT].rsp_valid),

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

logic sd_data_idle;

assign irq_lines[SD_DATA_IDLE] = sd_data_idle;

logic sd_card_detect_debounced_n;

debouncer#(.DEBOUNCE_CYCLES(75000), .DEFAULT_OUT(1'b1)) sd_card_detect_debouncer(
    .clock_i(ctrl_cpu_clock),
    .signal_i(sd_card_detect_n),
    .signal_o(sd_card_detect_debounced_n)
);

assign irq_lines[SD_INSERT_IRQ] = sd_card_detect_debounced_n ^ gp_out[0][GPIO_OUT0__SD_CARD_POLARITY];

gpio#(
    .NUM_IN_PORTS(GPIO_IN_PORTS),
    .NUM_OUT_PORTS(GPIO_OUT_PORTS))
gpio(
    .clock_i(ctrl_cpu_clock),

    .req_addr_i(io_ports_bus[IO_PORT_GPIO].req_addr),
    .req_data_i(io_ports_bus[IO_PORT_GPIO].req_data),
    .req_write_i(io_ports_bus[IO_PORT_GPIO].req_write),
    .req_valid_i(io_ports_bus[IO_PORT_GPIO].req_valid),
    .req_ready_o(io_ports_bus[IO_PORT_GPIO].req_ack),

    .rsp_data_o(io_ports_bus[IO_PORT_GPIO].rsp_data),
    .rsp_valid_o(io_ports_bus[IO_PORT_GPIO].rsp_valid),

    .gp_in( '{ {26'b0, sd_data_idle, sd_card_detect_debounced_n, buffered_switches} } ),
    .gp_out( gp_out )
);

spi_ctrl spi_flash(
    .cpu_clock_i(ctrl_cpu_clock),
    //.spi_ref_clock_i(bus_clock_50),
    .spi_ref_clock_i(board_clock),
    .irq(),

    .ctrl(io_ports_bus[IO_PORT_SPI]),

    .spi_cs_n_o(spi_cs_n),
    .spi_dq_io(spi_dq),
    .spi_clk_o(spi_clk),

    .dma(cache_ports[CACHE_PORT_IDX_SPI_FLASH])
);

uart_ctrl#(.ClockDivider(SIM_MODE ? 10 : CTRL_CLOCK_HZ / UART_BAUD), .SimMode(SIM_MODE)) uart_ctrl(
    .clock( ctrl_cpu_clock ),

    .ctrl(io_ports_bus[IO_PORT_UART]),

    .intr_send_ready_o(irq_lines[UART_SEND_IRQ]),
    .intr_recv_ready_o(irq_lines[UART_RECV_IRQ]),

    .uart_tx(uart_tx),
    .uart_rx(uart_rx)
);

sd sd_ctrl(
    .ctrl_clock_i(ctrl_cpu_clock),

    .ctrl(io_ports_bus[IO_PORT_SD]),

    .ctrl_data_idle_irq_o(sd_data_idle),

    .dma(cache_ports[CACHE_PORT_IDX_SD]),


    .sd_default_speed_clock_i(bus_clock_25),
    .sd_high_speed_clock_i(bus_clock_50),

    .sd_cmd_io(sd_cmd),
    .sd_data_io(sd_data),
    .sd_clk_o(sd_clk)
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
    for(i=FIRST_EMPTY_BASE_IRQ; i<16; ++i)
        assign irq_lines[i] = 1'b0;
    for(i=FIRST_EMPTY_AUX_IRQ; i<32; ++i)
        assign irq_lines[i] = 1'b0;
endgenerate

always_ff@(posedge ctrl_cpu_clock) begin
    leds[0] <= gp_out[0][GPIO_OUT0__DISPLAY8_RESET];
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

logic [68:0]dbglogger_data, dbglogger_data_pending;
logic dbglogger_trigger = 1'b0, dbglogger_trigger_pending = 1'b0;
logic dbglogging = 1'b0;

always_ff@(posedge ctrl_cpu_clock) begin
    dbglogger_trigger <= 1'b0;

    if( dbglogger_trigger_pending && (ctrl_dbus.rsp_valid || dbglogger_data_pending[68]) ) begin
        dbglogger_data <= dbglogger_data_pending;
        if( !dbglogger_data_pending[68] ) 
            dbglogger_data[31:0] <= ctrl_dbus.rsp_data;
        dbglogger_trigger <= 1'b1;
        dbglogger_trigger_pending <= 1'b0;
    end

    if( ctrl_dbus.req_valid && ctrl_dbus.req_ack && ctrl_dbus.req_addr[31:16]==16'h8081 && dbglogging ) begin
        dbglogger_data_pending <= { ctrl_dBus_cmd_payload_wr, ctrl_dBus_cmd_payload_mask, ctrl_dbus.req_addr, ctrl_dbus.req_data };
        dbglogger_trigger_pending <= 1'b1;
    end

    if( inst_cache_ports[0].req_ack && inst_cache_ports[0].req_valid && inst_cache_ports[0].req_addr==32'h80014e24 )
        dbglogging <= 1'b1;
end

dbglogger dbglogger(
    .clk_i(ctrl_cpu_clock),
    .rst_i(!ctrl_cpu_reset || !clocks_locked),

    .log_data_i(dbglogger_data),
    .log_enable_i(dbglogger_trigger),

    .ctrl_req_valid_i(io_ports_bus[IO_PORT_DBG_LOGGER].req_valid),
    .ctrl_req_addr_i(io_ports_bus[IO_PORT_DBG_LOGGER].req_addr),
    .ctrl_req_data_i(io_ports_bus[IO_PORT_DBG_LOGGER].req_data),
    .ctrl_req_write_i(io_ports_bus[IO_PORT_DBG_LOGGER].req_write),
    .ctrl_req_ack_o(io_ports_bus[IO_PORT_DBG_LOGGER].req_ack),

    .ctrl_rsp_valid_o(io_ports_bus[IO_PORT_DBG_LOGGER].rsp_valid),
    .ctrl_rsp_data_o(io_ports_bus[IO_PORT_DBG_LOGGER].rsp_data)
);








////////////////////////////////////////////////////////////////////////////////
// Start of Apple II only hardware region
////////////////////////////////////////////////////////////////////////////////
sync_bus#(.DATA_WIDTH(8), .ADDR_WIDTH(16)) bus8_cpu(), bus8_mem();
sync_bus_write_mask#(.DATA_WIDTH(8), .ADDR_WIDTH(32)) bus8_expanded();

wire apple_cpu_sync, apple_cpu_vector_pull, apple_cpu_memory_lock;
wire apple_dbg_halt;
wire [7:0] apple_cpu_dbg_reg_a, apple_cpu_dbg_reg_x, apple_cpu_dbg_reg_y, apple_cpu_dbg_reg_s, apple_cpu_dbg_reg_p;


wire cpu8_req_valid_divided, cpu8_req_ack_divided;

sar6502_sync apple_cpu(
    .clock_i( ctrl_cpu_clock ),

    .reset_i( gp_out[0][GPIO_OUT0__6502_RESET] ),
    .nmi_i( 1'b0 ),
    .irq_i( 1'b0 ),
    .set_overflow_i( 1'b0 ),

    .bus_req_valid_o( cpu8_req_valid_divided ),
    .bus_req_address_o( bus8_cpu.req_addr ),
    .bus_req_write_o( bus8_cpu.req_write ),
    .bus_req_ack_i( cpu8_req_ack_divided ),
    .bus_req_data_o( bus8_cpu.req_data ),
    .bus_rsp_valid_i( bus8_cpu.rsp_valid ),
    .bus_rsp_data_i( bus8_cpu.rsp_data ),

    .sync_o( apple_cpu_sync ),
    .vector_pull_o( apple_cpu_vector_pull ),
    .memory_lock_o( apple_cpu_memory_lock ),

    .dbg_reg_a( apple_cpu_dbg_reg_a ),
    .dbg_reg_x( apple_cpu_dbg_reg_x ),
    .dbg_reg_y( apple_cpu_dbg_reg_y ),
    .dbg_reg_s( apple_cpu_dbg_reg_s ),
    .dbg_reg_p( apple_cpu_dbg_reg_p )
);

freq_div_bus freq_div_6502(
    .clock_i( ctrl_cpu_clock ),
    .clock_enable_i( apple_dbg_halt ),
    .ctl_div_nom_i( BUS8_FREQ_DIV ),
    .ctl_div_denom_i( 16'd1 ),
    .reset_i( gp_out[0][GPIO_OUT0__FREQ_DIV_RESET] ),

    .slow_cmd_valid_i( cpu8_req_valid_divided ),
    .slow_cmd_ready_o( cpu8_req_ack_divided ),

    .fast_cmd_valid_o( bus8_cpu.req_valid ),
    .fast_cmd_ready_i( bus8_cpu.req_ack )
);

dbg6502 debugger(
    .clk_i( ctrl_cpu_clock ),

    .cpu_req_valid_i( cpu8_req_valid_divided ),
    .cpu_req_ack_i( cpu8_req_ack_divided ),
    .cpu_req_write_i( bus8_cpu.req_write ),
    .cpu_req_addr_i( bus8_cpu.req_addr ),
    .cpu_req_write_data_i( bus8_cpu.req_data ),

    .cpu_sync_i( apple_cpu_sync ),
    .cpu_memlock_i( apple_cpu_memory_lock ),
    .cpu_vector_pull_i( apple_cpu_vector_pull ),

    .cpu_reg_a( apple_cpu_dbg_reg_a ),
    .cpu_reg_x( apple_cpu_dbg_reg_x ),
    .cpu_reg_y( apple_cpu_dbg_reg_y ),
    .cpu_reg_s( apple_cpu_dbg_reg_s ),
    .cpu_reg_p( apple_cpu_dbg_reg_p ),

    .ctrl( io_ports_bus[IO_PORT_6502_DEBUGGER] ),
    .ctrl_intr_o( irq_lines[DBG_6502_IRQ] ),

    .n_halt_o( apple_dbg_halt )
);

logic apple_io_periph_req_valid[a2_io::NumPeripherals], apple_io_periph_req_ack[a2_io::NumPeripherals],
      apple_io_periph_req_write[a2_io::NumPeripherals], apple_io_periph_rsp_valid[a2_io::NumPeripherals];
logic [7:0] apple_io_periph_req_write_data[a2_io::NumPeripherals], apple_io_periph_rsp_read_data[a2_io::NumPeripherals];
logic [15:0] apple_io_periph_req_addr[a2_io::NumPeripherals];

apple_io apple_io_block(
    .clock_i( ctrl_cpu_clock ),

    .cpu_bus( bus8_cpu ),

    .perph_req_valid_o( apple_io_periph_req_valid ),
    .perph_req_ack_i( apple_io_periph_req_ack ),
    .perph_req_addr_o( apple_io_periph_req_addr ),
    .perph_req_write_o( apple_io_periph_req_write ),
    .perph_req_write_data_o( apple_io_periph_req_write_data ),

    .perph_rsp_valid_i( apple_io_periph_rsp_valid ),
    .perph_rsp_read_data_i( apple_io_periph_rsp_read_data ),

    .ctrl(io_ports_bus[IO_PORT_APPLE_IO]),

    .ctrl_intr_o( ctrl_software_interrupt )
);

apple_pager pager(
    .clock_i( ctrl_cpu_clock ),

    .cpu_req_valid_i( bus8_expanded.req_valid ),
    .cpu_req_write_i( bus8_expanded.req_write_mask[0] ),
    .cpu_req_addr_i( apple_io_periph_req_addr[a2_io::Mem] ),

    .mem_req_addr_o( bus8_expanded.req_addr ),

    .ctrl(io_ports_bus[IO_PORT_APPLE_PAGER])
);

assign bus8_expanded.req_valid = apple_io_periph_req_valid[a2_io::Mem];
assign apple_io_periph_req_ack[a2_io::Mem] = bus8_expanded.req_ack;
assign bus8_expanded.req_write_mask = apple_io_periph_req_write[a2_io::Mem];
assign bus8_expanded.req_data = apple_io_periph_req_write_data[a2_io::Mem];
assign apple_io_periph_rsp_valid[a2_io::Mem] = bus8_expanded.rsp_valid;
assign apple_io_periph_rsp_read_data[a2_io::Mem] = bus8_expanded.rsp_data;

bus_width_adjust bus8_width_adjuster(
    .clock_i( ctrl_cpu_clock ),

    .north_port(bus8_expanded),
    .south_port( cache_ports[CACHE_PORT_IDX_6502] )
);

apple2_diskette_controller a2_disk(
    .clk_i(ctrl_cpu_clock),
    .reset_i(gp_out[0][GPIO_OUT0__A2_DISK_CTRL_RESET]),

    .ctrl(io_ports_bus[IO_PORT_APPLE_DISKETTE]),

    .cpu_req_valid_i( apple_io_periph_req_valid[a2_io::Diskette] ),
    .cpu_req_ack_o( apple_io_periph_req_ack[a2_io::Diskette] ),
    .cpu_req_addr_i( apple_io_periph_req_addr[a2_io::Diskette] ),
    .cpu_req_write_i( apple_io_periph_req_write[a2_io::Diskette] ),
    .cpu_req_write_data_i( apple_io_periph_req_write_data[a2_io::Diskette] ),
    .cpu_rsp_valid_o( apple_io_periph_rsp_valid[a2_io::Diskette] ),
    .cpu_rsp_read_data_o( apple_io_periph_rsp_read_data[a2_io::Diskette] ),

    .dma( cache_ports[CACHE_PORT_IDX_APPLE_DISK] )
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
    if( bus8_cpu.req_valid && !bus8_cpu.req_write && apple_cpu_sync ) begin
        debug_display_data[15:0] <= bus8_cpu.req_addr;
        debug_pending_req <= 1'b1;
    end

    if( debug_pending_req == 1'b1 && bus8_cpu.rsp_valid ) begin
        debug_display_data[23:16] = bus8_cpu.rsp_data;
        debug_pending_req <= 1'b0;
    end

    if( bus8_cpu.req_valid && bus8_cpu.req_ack ) begin
        debug_display_point <= debug_display_point + 1;
    end
end

endmodule
