`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 08/16/2026 12:00:00 PM
// Design Name:
// Module Name: a2_disk_sim_top
// Project Name:
// Target Devices:
// Tool Versions:
// Description: Self checking testbench for apple2_diskette_controller.
//
//              Two phases are run:
//              Phase A - a byte aligned track (every byte has bit 7 set), so the
//                        shift register never loses byte alignment and the
//                        recovered nibble stream can be compared index for index
//                        against the golden track image. This is what catches
//                        DMA refill, track wrap and bit rate bugs.
//              Phase B - a DOS 3.3 shaped track with real 10 bit self sync cells,
//                        address and data fields. Checked by locating the field
//                        prologues in the recovered stream, which exercises
//                        re-synchronisation after the sync cells.
//
// Dependencies: sync_bus_interface.sv, freq_div_bus.sv,
//               apple2_diskette_controller.sv
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module a2_disk_sim_top(
    );

// ===========================================================================
// Configuration
// ===========================================================================

localparam DMA_WIDTH = 128;                 // CACHELINE_BITS in top.sv
localparam DMA_BYTES = DMA_WIDTH/8;

localparam MEM_WORDS = 2048;                // 32KiB of DMA-able memory
localparam TRACK_BASE = 32'h0000_1000;      // must be DMA_BYTES aligned

// Extra control clocks of latency the memory model adds before responding to a
// DMA read. 0 is the fastest a real cache hit could be; raise it to stress the
// controller's refill pipeline.
localparam DMA_RSP_LATENCY = 3;

// The Apple CPU runs at ~1.02MHz against a ~75.8MHz control clock.
localparam APPLE_CYCLE_DIV = 74;

// A Disk ][ bit cell is 4us, i.e. 4 Apple cycles. freq_div_bus emits one
// fast_cmd every (nom/denom + 1) enabled cycles, so nom=3/denom=1 gives 4.
localparam BIT_RATIO_NUM = 16'd3;
localparam BIT_RATIO_DENOM = 16'd1;
localparam APPLE_CYCLES_PER_BIT = BIT_RATIO_NUM/BIT_RATIO_DENOM + 1;

// The controller shifts dma_data[0][track_pos[6:0]] out, i.e. bit 0 of the
// 128 bit DMA word leaves first, which makes the in-memory bit stream little
// endian within each byte. The Apple II shifts disk bytes out MSB first, so
// each byte has to be bit reversed on the way into memory. Set to 0 if the
// software side is ever changed to store the stream MSB first per byte.
localparam BIT_REVERSE_BYTES = 1;

// Register map, per CompuSar.srcs/saros/saros/apple2_disk.cpp
localparam REG_TRACK_DATA_ADDR   = 16'h0000;
localparam REG_TRACK_LENGTH_BITS = 16'h0004;
localparam REG_TRACK_POS_BITS    = 16'h0008;
localparam REG_MOTOR_SPIN_RATIO  = 16'h000c;
localparam REG_MOTOR_CONTROL     = 16'h0010;
localparam   MOTOR_CONTROL__MOTOR_ON       = 32'h0000_0001;
localparam   MOTOR_CONTROL__RESET_FREQ_DIV = 32'h0000_0002;

// ===========================================================================
// Clock and Apple cycle generation
// ===========================================================================

logic ctrl_clk;

initial begin
    // ~75.8MHz control clock
    ctrl_clk = 1'b0;
    forever begin
        #6.598 ctrl_clk = 1'b1;
        #6.598 ctrl_clk = 1'b0;
    end
end

// The controller treats cpu_bus_valid_i && cpu_bus_ack_i as "an Apple cycle
// happened". Produce a single control clock wide pulse at the Apple rate.
logic cpu_bus_valid = 1'b0, cpu_bus_ack = 1'b0;
int apple_div_counter = 0;
int apple_cycle_count = 0;

wire apple_cycle;
assign apple_cycle = cpu_bus_valid && cpu_bus_ack;

always_ff@(posedge ctrl_clk) begin
    if( apple_div_counter == APPLE_CYCLE_DIV-1 ) begin
        apple_div_counter <= 0;
        cpu_bus_valid <= 1'b1;
        cpu_bus_ack <= 1'b1;
        apple_cycle_count <= apple_cycle_count + 1;
    end else begin
        apple_div_counter <= apple_div_counter + 1;
        cpu_bus_valid <= 1'b0;
        cpu_bus_ack <= 1'b0;
    end
end

// ===========================================================================
// DUT
// ===========================================================================

logic reset = 1'b1;

sync_bus#(.DATA_WIDTH(32), .ADDR_WIDTH(16)) ctrl();
sync_bus_write_mask#(.DATA_WIDTH(DMA_WIDTH), .ADDR_WIDTH(32)) dma();

logic cpu_req_valid = 1'b0, cpu_req_write = 1'b0;
logic [15:0] cpu_req_addr = 16'h00ec;       // $C0EC equivalent, read data latch
logic [7:0] cpu_req_write_data = 8'h00;
wire cpu_req_ack, cpu_rsp_valid;
wire [7:0] cpu_rsp_read_data;

apple2_diskette_controller dut(
    .clk_i(ctrl_clk),
    .reset_i(reset),

    .ctrl(ctrl),

    .cpu_req_valid_i(cpu_req_valid),
    .cpu_req_ack_o(cpu_req_ack),
    .cpu_req_addr_i(cpu_req_addr),
    .cpu_req_write_i(cpu_req_write),
    .cpu_req_write_data_i(cpu_req_write_data),

    .cpu_rsp_valid_o(cpu_rsp_valid),
    .cpu_rsp_read_data_o(cpu_rsp_read_data),

    .cpu_bus_valid_i(cpu_bus_valid),
    .cpu_bus_ack_i(cpu_bus_ack),

    .dma(dma)
);

// ===========================================================================
// DMA memory model
// ===========================================================================

logic [DMA_WIDTH-1:0] memory[MEM_WORDS];

int dma_read_count = 0;
logic dma_saw_x_addr = 1'b0;

// The interface members are driven through local registers so that the always_ff
// below is their only procedural driver.
logic dma_req_ack = 1'b0, dma_rsp_valid = 1'b0;
logic [DMA_WIDTH-1:0] dma_rsp_data = '0;

assign dma.req_ack = dma_req_ack;
assign dma.rsp_valid = dma_rsp_valid;
assign dma.rsp_data = dma_rsp_data;

// Pending response shift chain, to model DMA_RSP_LATENCY control clocks of
// read latency.
logic dma_rsp_pending[DMA_RSP_LATENCY+1] = '{ default: 1'b0 };
logic [DMA_WIDTH-1:0] dma_rsp_pending_data[DMA_RSP_LATENCY+1];

always_ff@(posedge ctrl_clk) begin
    // Advance the latency chain into the response port.
    dma_rsp_valid <= dma_rsp_pending[0];
    dma_rsp_data <= dma_rsp_pending_data[0];
    for( int i=0; i<DMA_RSP_LATENCY; ++i ) begin
        dma_rsp_pending[i] <= dma_rsp_pending[i+1];
        dma_rsp_pending_data[i] <= dma_rsp_pending_data[i+1];
    end
    dma_rsp_pending[DMA_RSP_LATENCY] <= 1'b0;

    if( dma.req_valid )
        dma_req_ack <= 1'b1;

    if( dma.req_valid && dma.req_ack ) begin
        automatic logic [31:0] word_addr = dma.req_addr >> $clog2(DMA_BYTES);

        dma_req_ack <= 1'b0;

        if( ^dma.req_addr === 1'bX ) begin
            // Catch an undriven base address rather than silently propagating X
            // through the whole bit stream.
            if( !dma_saw_x_addr )
                $display("[%0t] DMA ERROR: req_addr contains X/Z (%h) - is the track base address register driven?",
                         $time, dma.req_addr);
            dma_saw_x_addr <= 1'b1;
        end else if( word_addr >= MEM_WORDS ) begin
            $display("[%0t] DMA ERROR: req_addr %h (word %0d) is outside the modelled memory",
                     $time, dma.req_addr, word_addr);
        end

        if( dma.req_write_mask != 0 ) begin
            $display("[%0t] DMA ERROR: unexpected write, mask %h", $time, dma.req_write_mask);
        end else begin
            dma_rsp_pending[DMA_RSP_LATENCY] <= 1'b1;
            dma_rsp_pending_data[DMA_RSP_LATENCY] <= memory[word_addr % MEM_WORDS];
            dma_read_count <= dma_read_count + 1;
        end
    end
end

// ===========================================================================
// Control CPU bus tasks
// ===========================================================================

initial begin
    ctrl.req_valid = 1'b0;
    ctrl.req_write = 1'b0;
    ctrl.req_addr = 16'h0000;
    ctrl.req_data = 32'h0000_0000;
end

task wait_ctrl_ack();
    @(posedge ctrl_clk);
    while( !ctrl.req_ack )
        @(posedge ctrl_clk);
endtask

// Assumes we are already at a negative edge of the control clock, and leaves us
// at one.
task ctrl_write(input [15:0] addr, input [31:0] data);
    ctrl.req_valid = 1'b1;
    ctrl.req_addr = addr;
    ctrl.req_data = data;
    ctrl.req_write = 1'b1;

    wait_ctrl_ack();

    @(negedge ctrl_clk);
    ctrl.req_valid = 1'b0;
endtask

task ctrl_read(input [15:0] addr, output [31:0] data);
    ctrl.req_valid = 1'b1;
    ctrl.req_write = 1'b0;
    ctrl.req_addr = addr;

    wait_ctrl_ack();

    @(negedge ctrl_clk);
    ctrl.req_valid = 1'b0;

    @(posedge ctrl_clk);
    while( !ctrl.rsp_valid )
        @(posedge ctrl_clk);
    data = ctrl.rsp_data;

    @(negedge ctrl_clk);
endtask

// ===========================================================================
// Track image construction
// ===========================================================================

// Golden reference: the disk byte stream, MSB first per byte, as the Apple would
// see it. Phase A compares the recovered nibbles against this directly.
localparam MAX_TRACK_BYTES = 8192;
logic [7:0] track_bytes[MAX_TRACK_BYTES];
int track_num_bytes;

// Bit level image, used for Phase B where self sync cells are not byte aligned.
localparam MAX_TRACK_BITS = MAX_TRACK_BYTES*8;
logic track_bits[MAX_TRACK_BITS];
int track_num_bits;

// Number of 10 bit self sync cells in the image. Each one assembles into exactly
// one 0xFF in the shift register, so it is needed to work out how many bytes the
// Apple sees in one revolution.
int track_num_sync_cells;

function automatic logic [7:0] bit_reverse(input logic [7:0] v);
    bit_reverse = { v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7] };
endfunction

task clear_track();
    track_num_bytes = 0;
    track_num_bits = 0;
    track_num_sync_cells = 0;
endtask

// Append a raw bit to the bit level image.
task emit_bit(input logic b);
    track_bits[track_num_bits] = b;
    track_num_bits = track_num_bits + 1;
endtask

// Append a normal 8 bit disk byte: recorded in both representations.
task emit_byte(input logic [7:0] v);
    track_bytes[track_num_bytes] = v;
    track_num_bytes = track_num_bytes + 1;
    for( int i=7; i>=0; --i )
        emit_bit(v[i]);
endtask

// Append a self sync byte: 0xFF followed by two zero bits, i.e. a 10 bit cell.
// Only meaningful in the bit level image, so it is deliberately not added to
// track_bytes.
task emit_self_sync();
    for( int i=7; i>=0; --i )
        emit_bit(1'b1);
    emit_bit(1'b0);
    emit_bit(1'b0);
    track_num_sync_cells = track_num_sync_cells + 1;
endtask

// Pad the bit image out to a whole number of DMA words. The controller wraps
// track_pos at track_data_length and independently wraps fetch_offset at the
// same value, so keeping the length DMA aligned makes the two wraps coincide.
task pad_track_to_dma_word();
    while( track_num_bits % DMA_WIDTH != 0 )
        emit_bit(1'b0);
endtask

// Copy the bit level image into the DMA memory model at TRACK_BASE.
task load_track_into_memory();
    for( int w=0; w<MEM_WORDS; ++w )
        memory[w] = '0;

    for( int i=0; i<track_num_bits; ++i ) begin
        automatic int byte_index = i/8;
        automatic int bit_in_byte = i%8;
        automatic int stored_bit = BIT_REVERSE_BYTES ? bit_in_byte : 7-bit_in_byte;
        automatic int abs_bit = byte_index*8 + stored_bit;
        automatic int word = TRACK_BASE/DMA_BYTES + abs_bit/DMA_WIDTH;

        memory[word][abs_bit % DMA_WIDTH] = track_bits[i];
    end
endtask

// --- Phase A track: byte aligned, every byte has bit 7 set ------------------
//
// Deliberately covers more than 128 bits so the DMA refill path is exercised,
// and is not a multiple of 16 bytes' worth of interesting content so that the
// wrap does not accidentally line up with a byte boundary by luck alone.
task build_simple_track(input int num_bytes);
    clear_track();
    for( int i=0; i<num_bytes; ++i )
        // 0x80 | i, forced into the 0x80..0xFF range so bit 7 is always set.
        emit_byte( 8'h80 | i[6:0] );
    //pad_track_to_dma_word();
endtask

// --- Phase B track: DOS 3.3 shape ------------------------------------------

// The 64 legal 6-and-2 disk bytes.
logic [7:0] gcr62[64] = '{
    8'h96, 8'h97, 8'h9A, 8'h9B, 8'h9D, 8'h9E, 8'h9F, 8'hA6,
    8'hA7, 8'hAB, 8'hAC, 8'hAD, 8'hAE, 8'hAF, 8'hB2, 8'hB3,
    8'hB4, 8'hB5, 8'hB6, 8'hB7, 8'hB9, 8'hBA, 8'hBB, 8'hBC,
    8'hBD, 8'hBE, 8'hBF, 8'hCB, 8'hCD, 8'hCE, 8'hCF, 8'hD3,
    8'hD6, 8'hD7, 8'hD9, 8'hDA, 8'hDB, 8'hDC, 8'hDD, 8'hDE,
    8'hDF, 8'hE5, 8'hE6, 8'hE7, 8'hE9, 8'hEA, 8'hEB, 8'hEC,
    8'hED, 8'hEE, 8'hEF, 8'hF2, 8'hF3, 8'hF4, 8'hF5, 8'hF6,
    8'hF7, 8'hF9, 8'hFA, 8'hFB, 8'hFC, 8'hFD, 8'hFE, 8'hFF
};

// 4-and-4 ("odd/even") encoding: one byte becomes two, each carrying 4 bits in
// the odd or even positions with the gaps filled with 1s.
task emit_4and4(input logic [7:0] v);
    emit_byte( { 1'b1, v[7], 1'b1, v[5], 1'b1, v[3], 1'b1, v[1] } );
    emit_byte( { 1'b1, v[6], 1'b1, v[4], 1'b1, v[2], 1'b1, v[0] } );
endtask

localparam PHASE_B_VOLUME = 8'd254;
localparam PHASE_B_TRACK = 8'd17;
// A real track carries 16 sectors. Two is enough to prove the controller
// re-synchronises across a sync field and hands over a decodable stream, and
// keeps the simulation to a few tens of milliseconds of model time - raise this
// towards 16 for a full length track if you are willing to wait.
localparam PHASE_B_SECTORS = 2;

task build_dos33_track();
    clear_track();

    for( int sector=0; sector<PHASE_B_SECTORS; ++sector ) begin
        // Gap 1 / gap 3: self sync field
        for( int i=0; i<16; ++i )
            emit_self_sync();

        // Address field
        emit_byte(8'hD5); emit_byte(8'hAA); emit_byte(8'h96);
        emit_4and4(PHASE_B_VOLUME);
        emit_4and4(PHASE_B_TRACK);
        emit_4and4(sector[7:0]);
        emit_4and4(PHASE_B_VOLUME ^ PHASE_B_TRACK ^ sector[7:0]);
        emit_byte(8'hDE); emit_byte(8'hAA); emit_byte(8'hEB);

        // Gap 2
        for( int i=0; i<6; ++i )
            emit_self_sync();

        // Data field. The 342 payload bytes are drawn from the legal 6-and-2
        // set with a deterministic pattern rather than being a true nibblization
        // of a 256 byte sector - the controller is payload agnostic, all it cares
        // about is that every byte has bit 7 set.
        emit_byte(8'hD5); emit_byte(8'hAA); emit_byte(8'hAD);
        for( int i=0; i<342; ++i )
            emit_byte( gcr62[ (i*7 + sector*13) % 64 ] );
        emit_byte( gcr62[ sector % 64 ] );       // stand-in checksum
        emit_byte(8'hDE); emit_byte(8'hAA); emit_byte(8'hEB);
    end

    pad_track_to_dma_word();
endtask

// ===========================================================================
// Apple CPU reader
// ===========================================================================
//
// Emulates the LDA $C0EC / BPL loop. The controller never clears the shift
// register on read; instead, once shift_register[7] is set the following shift
// loads a fresh single bit. So bit 7 going 0 -> 1 is exactly the "a new disk
// byte has assembled" event.

localparam MAX_CAPTURED = 16384;
logic [7:0] captured[MAX_CAPTURED];
int captured_count = 0;
longint captured_apple_cycle[MAX_CAPTURED];

logic reader_enable = 1'b0;
logic prev_bit7 = 1'b0;
int cpu_read_count = 0;

// Issue one read per Apple cycle. A real 6502 poll loop is slower, but polling
// at the maximum rate makes the capture deterministic and independent of the
// grace counter window.
task apple_read(output logic [7:0] data);
    @(negedge ctrl_clk);
    cpu_req_valid = 1'b1;
    cpu_req_write = 1'b0;

    @(posedge ctrl_clk);
    while( !cpu_req_ack )
        @(posedge ctrl_clk);

    @(negedge ctrl_clk);
    cpu_req_valid = 1'b0;

    @(posedge ctrl_clk);
    while( !cpu_rsp_valid )
        @(posedge ctrl_clk);
    data = cpu_rsp_read_data;
    cpu_read_count = cpu_read_count + 1;
endtask

initial begin : reader_thread
    forever begin
        automatic logic [7:0] data;

        if( !reader_enable ) begin
            @(posedge ctrl_clk);
            prev_bit7 = 1'b0;
            continue;
        end

        apple_read(data);

        if( data[7] && !prev_bit7 ) begin
            if( captured_count < MAX_CAPTURED ) begin
                captured[captured_count] = data;
                captured_apple_cycle[captured_count] = apple_cycle_count;
                captured_count = captured_count + 1;
            end
        end
        prev_bit7 = data[7];
    end
end

// ===========================================================================
// Checking helpers
// ===========================================================================

int errors = 0;

task check(input logic condition, input string message);
    if( !condition ) begin
        errors = errors + 1;
        $display("[%0t] FAIL: %s", $time, message);
    end else begin
        $display("[%0t] ok:   %s", $time, message);
    end
endtask

// Wait until captured_count reaches target, or give up after timeout_cycles
// Apple cycles and dump the controller state.
task wait_for_captured(input int target, input int timeout_cycles);
    automatic longint deadline = apple_cycle_count + timeout_cycles;

    while( captured_count < target && apple_cycle_count < deadline )
        @(posedge ctrl_clk);

    if( captured_count < target ) begin
        errors = errors + 1;
        $display("[%0t] FAIL: timed out waiting for %0d disk bytes, only got %0d",
                 $time, target, captured_count);
        $display("           track_pos=%0d track_data_length=%0d fetch_offset=%0d",
                 dut.track_pos, dut.track_data_length, dut.fetch_offset);
        $display("           shift_register=%h grace_counter=%0d should_bit_shift=%b",
                 dut.shift_register, dut.grace_counter, dut.should_bit_shift);
        $display("           dma_data_valid={%b,%b} dma_req_pending=%b motor_running=%b",
                 dut.dma_data_valid[1], dut.dma_data_valid[0],
                 dut.dma_req_pending, dut.motor_running);
        $display("           dma.req_valid=%b dma.req_addr=%h dma reads served=%0d",
                 dma.req_valid, dma.req_addr, dma_read_count);
    end
endtask

task start_motor();
    // Every ctrl write clears dma_data_valid and drops motor_running, so the
    // motor control register has to be written last.
    @(negedge ctrl_clk);
    ctrl_write(REG_TRACK_DATA_ADDR, TRACK_BASE);
    ctrl_write(REG_TRACK_LENGTH_BITS, track_num_bits);
    ctrl_write(REG_MOTOR_SPIN_RATIO, { BIT_RATIO_NUM, BIT_RATIO_DENOM });
    ctrl_write(REG_TRACK_POS_BITS, 32'h0000_0000);
    ctrl_write(REG_MOTOR_CONTROL, MOTOR_CONTROL__MOTOR_ON);
endtask

task stop_motor();
    @(negedge ctrl_clk);
    ctrl_write(REG_MOTOR_CONTROL, MOTOR_CONTROL__RESET_FREQ_DIV);
endtask

// ===========================================================================
// Phase A: byte aligned track, index for index comparison
// ===========================================================================

localparam PHASE_A_BYTES = 100;             // 800 bits: 6.25 DMA words

task phase_a();
    automatic logic [31:0] rd;
    automatic int to_capture;

    $display("");
    $display("=== Phase A: byte aligned track, %0d bytes ===", PHASE_A_BYTES);

    build_simple_track(PHASE_A_BYTES);
    load_track_into_memory();
    $display("[%0t] track: %0d bytes, %0d bits (%0d DMA words)",
             $time, track_num_bytes, track_num_bits, track_num_bits/DMA_WIDTH);

    captured_count = 0;
    start_motor();

    // Register read back
    ctrl_read(REG_TRACK_LENGTH_BITS, rd);
    check( rd == track_num_bits,
           $sformatf("track length read back as %0d, expected %0d", rd, track_num_bits) );

    reader_enable = 1'b1;

    // Ask for one and a half times round the track so that both the DMA refill
    // and the track wrap are covered.
    to_capture = PHASE_A_BYTES + PHASE_A_BYTES/2;
    // Each byte is 8 bits and each bit is APPLE_CYCLES_PER_BIT Apple cycles;
    // allow 4x that as the timeout.
    wait_for_captured( to_capture, to_capture*8*APPLE_CYCLES_PER_BIT*4 );

    reader_enable = 1'b0;

    // Compare what came back against the golden stream. The track is padded with
    // zero bits, and the padding is not part of track_bytes, so only compare the
    // first PHASE_A_BYTES entries and then whatever we got after the wrap.
    begin
        automatic int compared = 0;
        automatic int mismatches = 0;
        automatic int limit = captured_count < PHASE_A_BYTES ? captured_count : PHASE_A_BYTES;

        for( int i=0; i<limit; ++i ) begin
            compared++;
            if( captured[i] !== track_bytes[i] ) begin
                if( mismatches < 8 )
                    $display("[%0t]   byte %0d: got %h, expected %h",
                             $time, i, captured[i], track_bytes[i]);
                mismatches++;
            end
        end

        check( compared == PHASE_A_BYTES,
               $sformatf("recovered %0d of the first %0d disk bytes", compared, PHASE_A_BYTES) );
        // Only meaningful if something actually came back; otherwise the check
        // above has already failed and this one would pass vacuously.
        if( compared > 0 )
            check( mismatches == 0,
                   $sformatf("first pass over the track matches the golden image (%0d mismatches)",
                             mismatches) );
    end

    // The tail of the padding is zero bits, so the byte boundary after the wrap
    // is not guaranteed to line up. What must hold is that the stream restarts:
    // look for the start of the track image somewhere in the captured tail.
    if( captured_count > PHASE_A_BYTES ) begin
        automatic logic found = 1'b0;
        for( int i=PHASE_A_BYTES; i<captured_count-3 && !found; ++i ) begin
            if( captured[i] === track_bytes[0] && captured[i+1] === track_bytes[1] &&
                captured[i+2] === track_bytes[2] && captured[i+3] === track_bytes[3] )
                found = 1'b1;
        end
        check( found, "track wrapped and the image restarted from the beginning" );
    end

    // Bit rate: measure the Apple cycles between consecutive disk bytes. Each
    // byte is 8 bit cells.
    if( captured_count >= 12 ) begin
        automatic longint span = captured_apple_cycle[10] - captured_apple_cycle[2];
        automatic longint expected = 8 * 8 * APPLE_CYCLES_PER_BIT;
        check( span == expected,
               $sformatf("8 disk bytes took %0d Apple cycles, expected %0d",
                         span, expected) );
    end

    // track_pos should be advancing
    @(negedge ctrl_clk);
    ctrl_read(REG_TRACK_POS_BITS, rd);
    check( rd < track_num_bits,
           $sformatf("track_pos read back as %0d, within the track length %0d",
                     rd, track_num_bits) );

    check( dma_read_count > track_num_bits/DMA_WIDTH,
           $sformatf("DMA refilled more than once round the track (%0d reads)", dma_read_count) );
    check( !dma_saw_x_addr, "no X/Z ever appeared on the DMA address" );

    stop_motor();
endtask

// ===========================================================================
// Phase B: DOS 3.3 shaped track with self sync fields
// ===========================================================================

// Search the captured stream for the next occurrence of a 3 byte prologue,
// starting at 'from'. Returns the index of the first prologue byte, or -1.
function automatic int find_prologue(input int from, input logic [7:0] a,
                                     input logic [7:0] b, input logic [7:0] c);
    find_prologue = -1;
    for( int i=from; i+2<captured_count; ++i ) begin
        if( captured[i] === a && captured[i+1] === b && captured[i+2] === c ) begin
            find_prologue = i;
            break;
        end
    end
endfunction

function automatic logic [7:0] decode_4and4(input logic [7:0] hi, input logic [7:0] lo);
    decode_4and4 = ((hi << 1) | 8'h01) & lo;
endfunction

task phase_b();
    automatic int sectors_found = 0;
    automatic int idx = 0;
    automatic int bad_sectors = 0;

    $display("");
    $display("=== Phase B: DOS 3.3 shaped track, %0d sectors ===", PHASE_B_SECTORS);

    build_dos33_track();
    load_track_into_memory();
    $display("[%0t] track: %0d bits (%0d DMA words), %0d addressable disk bytes",
             $time, track_num_bits, track_num_bits/DMA_WIDTH, track_num_bytes);

    captured_count = 0;
    dma_read_count = 0;
    start_motor();

    reader_enable = 1'b1;
    // Wait for one full revolution's worth of assembled bytes. A normal byte
    // takes 8 bit cells, a self sync cell takes 10 and still yields one 0xFF, and
    // the zero padding at the end yields nothing - so one revolution is exactly
    // track_num_bytes + track_num_sync_cells bytes.
    wait_for_captured( track_num_bytes + track_num_sync_cells,
                       track_num_bits*APPLE_CYCLES_PER_BIT*2 );
    reader_enable = 1'b0;

    // Walk the recovered stream looking for the address and data fields. This is
    // what a real read routine does, and it is the only way to check the stream
    // once the 10 bit self sync cells have broken byte alignment.
    forever begin
        automatic int addr_idx = find_prologue(idx, 8'hD5, 8'hAA, 8'h96);
        automatic int data_idx;
        automatic logic [7:0] vol, trk, sec, chk;

        if( addr_idx < 0 )
            break;

        if( addr_idx + 11 >= captured_count )
            break;

        vol = decode_4and4( captured[addr_idx+3], captured[addr_idx+4] );
        trk = decode_4and4( captured[addr_idx+5], captured[addr_idx+6] );
        sec = decode_4and4( captured[addr_idx+7], captured[addr_idx+8] );
        chk = decode_4and4( captured[addr_idx+9], captured[addr_idx+10] );

        if( vol !== PHASE_B_VOLUME || trk !== PHASE_B_TRACK || sec >= PHASE_B_SECTORS ||
            chk !== (vol ^ trk ^ sec) ) begin
            $display("[%0t]   address field at %0d decoded badly: vol=%0d trk=%0d sec=%0d chk=%02h",
                     $time, addr_idx, vol, trk, sec, chk);
            bad_sectors++;
        end else begin
            data_idx = find_prologue(addr_idx+11, 8'hD5, 8'hAA, 8'hAD);
            if( data_idx < 0 || data_idx + 345 >= captured_count ) begin
                $display("[%0t]   sector %0d: no complete data field followed the address field",
                         $time, sec);
                bad_sectors++;
            end else begin
                sectors_found++;
                $display("[%0t]   sector %0d: address field at %0d, data field at %0d",
                         $time, sec, addr_idx, data_idx);
            end
        end

        idx = addr_idx + 11;
    end

    check( sectors_found >= PHASE_B_SECTORS,
           $sformatf("found %0d well formed sectors, expected %0d", sectors_found, PHASE_B_SECTORS) );
    check( bad_sectors == 0,
           $sformatf("no malformed fields in the recovered stream (%0d bad)", bad_sectors) );
    check( !dma_saw_x_addr, "no X/Z ever appeared on the DMA address" );

    stop_motor();
endtask

// ===========================================================================
// Main
// ===========================================================================

initial begin
    reset = 1'b1;
    repeat(10) @(posedge ctrl_clk);
    @(negedge ctrl_clk);
    reset = 1'b0;
    repeat(10) @(posedge ctrl_clk);

    phase_a();
    phase_b();

    $display("");
    if( errors == 0 )
        $display("=== PASS: all checks passed ===");
    else
        $display("=== FAIL: %0d check(s) failed ===", errors);

    $finish;
end

// Absolute backstop, in case a wait loop above is ever changed to be unbounded.
// A revolution of the Phase B track is already tens of milliseconds of model
// time, so this has to be generous; the per-phase timeouts are what should
// normally fire.
initial begin
    #250_000_000;
    $display("=== FAIL: global timeout ===");
    $finish;
end

endmodule
