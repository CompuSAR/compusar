`timescale 1ns / 1ps

module cache#(
        ADDR_BITS = 32,
        CACHELINE_BITS = 128,
        NUM_CACHELINES = 1024,
        BACKEND_SIZE_BYTES = 0,
        INIT_FILE = "none",
        STATE_INIT = "none",
        NUM_PORTS = 1
    )(
        input                                                           clock_i,

        input [15:0]                                                    ctrl_cmd_addr_i,
        input                                                           ctrl_cmd_valid_i,
        output                                                          ctrl_cmd_ready_o,
        input                                                           ctrl_cmd_write_i,
        input [31:0]                                                    ctrl_cmd_data_i,
        output                                                          ctrl_rsp_valid_o,
        output [31:0]                                                   ctrl_rsp_data_o,

        input                                                           port_cmd_valid_i[NUM_PORTS],
        input [ADDR_BITS-1:0]                                           port_cmd_addr_i[NUM_PORTS],
        output                                                          port_cmd_ready_o[NUM_PORTS],
        input [CACHELINE_BITS/8-1:0]                                    port_cmd_write_mask_i[NUM_PORTS],
        input [CACHELINE_BITS-1:0]                                      port_cmd_write_data_i[NUM_PORTS],
        output                                                          port_rsp_valid_o[NUM_PORTS],
        output [CACHELINE_BITS-1:0]                                     port_rsp_read_data_o[NUM_PORTS],

        output logic                                                    backend_cmd_valid_o,
        output logic [ADDR_BITS-1:0]                                    backend_cmd_addr_o,
        input                                                           backend_cmd_ready_i,
        output logic                                                    backend_cmd_write_o,
        output [CACHELINE_BITS-1:0]                                     backend_cmd_write_data_o,
        input                                                           backend_rsp_valid_i,
        input  [CACHELINE_BITS-1:0]                                     backend_rsp_read_data_i
    );

localparam LINES_ADDR_BITS = $clog2(NUM_CACHELINES);
localparam BACKEND_COMPLEMENTARY_ADDRESS = $clog2(BACKEND_SIZE_BYTES) - LINES_ADDR_BITS - $clog2(CACHELINE_BITS/8);

localparam EMPTY_WRITE_MASK = { CACHELINE_BITS/8{1'b0} };
localparam FULL_WRITE_MASK = { CACHELINE_BITS/8{1'b1} };

localparam ADDR_CACHELINE_OFFSET_LOW = 0;
localparam ADDR_CACHELINE_OFFSET_HIGH = $clog2(CACHELINE_BITS/8) - 1;
localparam ADDR_CACHELINE_ADDR_LOW = ADDR_CACHELINE_OFFSET_HIGH + 1;
localparam ADDR_CACHELINE_ADDR_HIGH = ADDR_CACHELINE_ADDR_LOW + LINES_ADDR_BITS - 1;
localparam ADDR_COMPLEMENTARY_LOW = ADDR_CACHELINE_ADDR_HIGH + 1;
localparam ADDR_COMPLEMENTARY_HIGH = $clog2(BACKEND_SIZE_BYTES) - 1;

function logic[ADDR_CACHELINE_ADDR_HIGH:ADDR_CACHELINE_ADDR_LOW] extract_cacheline_addr(input [ADDR_BITS-1:0] address);
    extract_cacheline_addr = address[ADDR_CACHELINE_ADDR_HIGH:ADDR_CACHELINE_ADDR_LOW];
endfunction

function logic[ADDR_COMPLEMENTARY_HIGH:ADDR_COMPLEMENTARY_LOW] extract_complement_addr(input [ADDR_BITS-1:0] address);
    extract_complement_addr = address[ADDR_COMPLEMENTARY_HIGH:ADDR_COMPLEMENTARY_LOW];
endfunction

function logic[ADDR_BITS-1:0] compose_address(
        input [ADDR_COMPLEMENTARY_HIGH-ADDR_COMPLEMENTARY_LOW:0] complementary,
        input [ADDR_CACHELINE_ADDR_HIGH-ADDR_CACHELINE_ADDR_LOW:0] cacheline);
    compose_address = { complementary, cacheline, {$clog2(CACHELINE_BITS/8){1'b0}} };
endfunction

typedef struct packed {
    logic                                               initialized;
    logic                                               dirty;
    logic [BACKEND_COMPLEMENTARY_ADDRESS-1:0]           source_address;
} CachelineMetadata;

logic [LINES_ADDR_BITS-1:0]             rd_addr, wr_addr,
                                        prev_rd_addr = {{LINES_ADDR_BITS-1{1'b1}}, 1'b0}, // Any address that is not the first one.
                                        prev_wr_addr = {{LINES_ADDR_BITS-1{1'b1}}, 1'b0}; // Any address that is not the first one.

CachelineMetadata                       md_wr_din, prev_md_wr_din;
CachelineMetadata                       md_rd_dout, md_rd_dout_readback;
logic                                   md_wr_enable;

logic [CACHELINE_BITS-1:0]              cm_wr_existing_data, cm_wr_din_actual, prev_cm_wr_din;
logic                                   cm_wr_enable;
logic [CACHELINE_BITS-1:0]              cm_rd_dout, cm_rd_dout_readback;
logic                                   rd_enable;

logic [CACHELINE_BITS-1:0]              port_rsp_data;

assign md_rd_dout =
    prev_wr_addr==prev_rd_addr ?
    prev_md_wr_din :
    md_rd_dout_readback;

assign cm_rd_dout =
    prev_wr_addr==prev_rd_addr ?
    prev_cm_wr_din :
    cm_rd_dout_readback;

assign port_rsp_data = cm_rd_dout;

xpm_memory_sdpram#(
    .CLOCKING_MODE("common_clock"),
    .MEMORY_INIT_FILE(STATE_INIT),
    //.MEMORY_PRIMITIVE("distributed"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE($bits(CachelineMetadata)*NUM_CACHELINES),
    .USE_MEM_INIT(STATE_INIT != "none"),
    .SIM_ASSERT_CHK(1),

    .ADDR_WIDTH_A($clog2(NUM_CACHELINES)),
    .BYTE_WRITE_WIDTH_A($bits(CachelineMetadata)),
    .WRITE_DATA_WIDTH_A($bits(CachelineMetadata)),

    .ADDR_WIDTH_B($clog2(NUM_CACHELINES)),
    .READ_DATA_WIDTH_B($bits(CachelineMetadata)),
    .READ_LATENCY_B(1),
    .WRITE_MODE_B("read_first")
) cache_metadata(
    .clka( clock_i ),
    .addra( wr_addr ),
    .dina( md_wr_din ),
    .ena( md_wr_enable ),
    .injectdbiterra( 1'b0 ),
    .injectsbiterra( 1'b0 ),
    .wea( 1'b1 ),

    .clkb( clock_i ),
    .addrb( rd_addr ),
    .doutb( md_rd_dout_readback ),
    .enb( rd_enable ),
    .regceb( 1'b1 ),
    .rstb( 1'b0 ),

    .sleep( 1'b0 )
);

xpm_memory_sdpram#(
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
//    .CASCADE_HEIGHT(1),
    .MEMORY_INIT_FILE(INIT_FILE),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(CACHELINE_BITS * NUM_CACHELINES),
//    .SIM_ASSERT_CHK(1),
    .USE_MEM_INIT(INIT_FILE != "none"),
    .SIM_ASSERT_CHK(1),

    .ADDR_WIDTH_A($clog2(NUM_CACHELINES)),
    .WRITE_DATA_WIDTH_A(CACHELINE_BITS),
    .BYTE_WRITE_WIDTH_A(CACHELINE_BITS),

    .ADDR_WIDTH_B($clog2(NUM_CACHELINES)),
    .READ_DATA_WIDTH_B(CACHELINE_BITS),
    .READ_LATENCY_B(1),
    .WRITE_MODE_B("read_first"),

    .WRITE_PROTECT(1)
) cache_mem(
    .clka( clock_i ),
    .addra( wr_addr ),
    .dina( cm_wr_din_actual ),
    .ena( cm_wr_enable ),
    .injectdbiterra( 1'b0 ),
    .injectsbiterra( 1'b0 ),
    .wea( 1'b1 ),

    .clkb( clock_i ),
    .addrb( rd_addr ),
    .doutb( cm_rd_dout_readback ),
    .enb( rd_enable ),
    .regceb( 1'b1 ),
    .rstb( 1'b0 ),

    .sleep( 1'b0 )
);

enum { IDLE, LOOKUP, EVICTING, FETCHING, RESULT } command_state = IDLE, command_state_next, proposed_command_state_next;
logic set_command_active, rsp_valid;
struct {
    logic [ADDR_BITS-1:0]                                       address;
    logic [CACHELINE_BITS/8-1:0]                                write_mask;
    logic [CACHELINE_BITS-1:0]                                  write_data;

    logic [$clog2(NUM_PORTS)-1:0]                               active_port;
} active_command;

assign backend_cmd_write_data_o = cm_rd_dout;

byte_selector#(CACHELINE_BITS/8) result_selector(
    .mask(active_command.write_mask),
    .included(active_command.write_data),
    .complement(cm_wr_existing_data),
    .result(cm_wr_din_actual)
);


genvar i;
generate
    for(i=0; i<NUM_PORTS; i++) begin : port_state
        wire pending, prev_pending;

        assign pending = port_cmd_valid_i[i];
        assign port_cmd_ready_o[i] = !prev_pending && proposed_command_state_next==IDLE;
        assign port_rsp_read_data_o[i] = port_rsp_data;
        assign port_rsp_valid_o[i] = rsp_valid && active_command.active_port==i;

        wire [$clog2(NUM_PORTS)-1:0] next_active;
        wire [$clog2(NUM_PORTS)-1:0] active_port = pending && !prev_pending ? i : next_active;
    end : port_state

    assign port_state[0].prev_pending = 1'b0;
    for(i=1; i<NUM_PORTS; i++) begin
        assign port_state[i].prev_pending = port_state[i-1].pending || port_state[i-1].prev_pending;
    end

    assign port_state[NUM_PORTS-1].next_active = 0;
    for(i=0; i<NUM_PORTS-1; i++) begin
        assign port_state[i].next_active = port_state[i+1].active_port;
    end
endgenerate

wire [$clog2(NUM_PORTS)-1:0] active_port = port_state[0].active_port;

function void do_cache_write();
    proposed_command_state_next = IDLE;

    wr_addr = extract_cacheline_addr( active_command.address );

    md_wr_din.dirty = 1'b1;
    md_wr_enable = 1'b1;

    cm_wr_enable = 1'b1;
    cm_wr_existing_data = cm_rd_dout;
endfunction

function void do_evict();
    backend_cmd_valid_o = 1'b1;
    backend_cmd_write_o = 1'b1;
    backend_cmd_addr_o = compose_address( md_rd_dout.source_address, extract_cacheline_addr(active_command.address) );

    if( backend_cmd_ready_i ) begin
        proposed_command_state_next = EVICTING;

        md_wr_din.source_address = extract_complement_addr(active_command.address);
        md_wr_din.initialized = 1'b1;
        md_wr_din.dirty = 1'b0;
        md_wr_enable = 1'b1;
    end
endfunction

function void handle_evict();
    if( active_command.write_mask == FULL_WRITE_MASK )
        do_cache_write();
    else
        do_fetch();
endfunction

function void do_fetch();
    backend_cmd_valid_o = 1'b1;
    backend_cmd_write_o = 1'b0;
    backend_cmd_addr_o =
        { active_command.address[ADDR_COMPLEMENTARY_HIGH:ADDR_CACHELINE_ADDR_LOW], {$clog2(CACHELINE_BITS/8){1'b0}} };

    if( backend_cmd_ready_i )
        proposed_command_state_next = FETCHING;
endfunction

function void handle_fetch();
    if( backend_rsp_valid_i ) begin
        wr_addr = extract_cacheline_addr(active_command.address);

        md_wr_enable = 1'b1;
        md_wr_din.source_address = extract_complement_addr(active_command.address);
        md_wr_din.initialized = 1'b1;

        cm_wr_enable = 1'b1;
        cm_wr_existing_data = backend_rsp_read_data_i;

        if( active_command.write_mask != EMPTY_WRITE_MASK ) begin
            md_wr_din.dirty = 1'b1;
            proposed_command_state_next = IDLE;
        end else begin
            md_wr_din.dirty = 1'b0;
            proposed_command_state_next = RESULT;
        end
    end
endfunction

function void handle_result();
    if( active_command.write_mask==EMPTY_WRITE_MASK ) begin
        // Read request
        rsp_valid = 1'b1;
    end

    proposed_command_state_next = IDLE;
endfunction

function void handle_lookup();
    if( active_command.write_mask==EMPTY_WRITE_MASK ) begin
        // Read
        if( md_rd_dout.initialized ) begin
            // Cacheline has data
            if( md_rd_dout.source_address == extract_complement_addr(active_command.address) ) begin
                // Cache hit
                proposed_command_state_next = IDLE;
                rsp_valid = 1'b1;
            end else begin
                // Cache miss
                if( md_rd_dout.dirty ) begin
                    do_evict();
                end else begin
                    do_fetch();
                end
            end
        end else begin
            // Cacheline is uninitialized
            do_fetch();
        end
    end else begin
        // Write
        if( md_rd_dout.initialized ) begin
            // Cacheline contains data
            if( md_rd_dout.source_address == extract_complement_addr(active_command.address) ) begin
                // Cache hit
                do_cache_write();
            end else begin
                // Cache miss
                if( md_rd_dout.dirty ) begin
                    do_evict();
                end else begin
                    if( active_command.write_mask == FULL_WRITE_MASK ) begin
                        // Writing complete cacheline in one go
                        do_cache_write();
                    end else begin
                        do_fetch();
                    end
                end
            end
        end else begin
            // Cacheline empty
            if( active_command.write_mask == FULL_WRITE_MASK ) begin
                // Writing complete cacheline in one go
                do_cache_write();
            end else begin
                do_fetch();
            end
        end
    end
endfunction

always_comb begin
    wr_addr = extract_cacheline_addr(active_command.address);
    md_wr_enable = 1'b0;

    // Default values (to avoid latches) for metadata din
    md_wr_din.initialized = 1'b1;
    md_wr_din.dirty = 1'b1;
    md_wr_din.source_address = extract_complement_addr(active_command.address);

    //rd_addr = extract_cacheline_addr( port_cmd_addr_i[active_port] );
    rd_addr = prev_rd_addr;
    rd_enable = 1'b0;

    set_command_active = 1'b0;
    cm_wr_enable = 1'b0;
    rsp_valid = 1'b0;

    backend_cmd_valid_o = 1'b0;
    backend_cmd_write_o = 1'bX;
    backend_cmd_addr_o = { ADDR_BITS{1'bX} };

    cm_wr_existing_data = cm_rd_dout;

    proposed_command_state_next = command_state;

    // Handle active commands
    case(command_state)
        IDLE: begin end
        LOOKUP: handle_lookup();
        EVICTING: handle_evict();
        FETCHING: handle_fetch();
        RESULT: handle_result();
    endcase

    // Handle new commands
    if( port_cmd_valid_i[active_port] && port_cmd_ready_o[active_port] ) begin
        // We have a pending command
        rd_addr = extract_cacheline_addr( port_cmd_addr_i[active_port] );

        rd_enable = 1'b1;

        set_command_active = 1'b1;
        command_state_next = LOOKUP;
    end else begin
        command_state_next = proposed_command_state_next;
    end
end

always_ff@(posedge clock_i) begin
    command_state <= command_state_next;

    if( set_command_active ) begin
        active_command.active_port <= active_port;
        active_command.address <= port_cmd_addr_i[active_port];
        active_command.write_mask <= port_cmd_write_mask_i[active_port];
        active_command.write_data <= port_cmd_write_data_i[active_port];
    end

    if( rd_enable ) begin
        prev_rd_addr <= rd_addr;
    end

    if( md_wr_enable ) begin
        prev_wr_addr <= wr_addr;
        prev_md_wr_din <= md_wr_din;
        prev_cm_wr_din <= cm_wr_din_actual;
    end
end

endmodule
