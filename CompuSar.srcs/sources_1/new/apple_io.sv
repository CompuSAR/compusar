`timescale 1ns / 1ps

module apple_io(
    input clock_i,

    input cpu_req_valid_i,
    output cpu_req_ack_o,
    input cpu_req_write_i,
    input [15:0] cpu_req_addr_i,
    input [7:0] cpu_req_data_i,

    output cpu_rsp_valid_o,
    output [7:0] cpu_rsp_data_o,

    output mem_req_valid_o,
    input mem_req_ack_i,
    output mem_req_write_o,
    output [15:0] mem_req_addr_o,
    output [7:0] mem_req_data_o,

    input mem_rsp_valid_i,
    input [7:0] mem_rsp_data_i,

    input ctrl_req_valid_i,
    input ctrl_req_write_i,
    input [15:0] ctrl_req_addr_i,
    input [31:0] ctrl_req_data_i,
    output ctrl_req_ack_o,

    output logic ctrl_rsp_valid_o,
    output logic[31:0] ctrl_rsp_data_o,

    output logic ctrl_intr_o = 1'b0
    );

logic io_op_pending = 1'b0;
logic io_rsp_valid = 1'b0;
logic io_req_write;
logic io_mem_req = 1'b0;
logic [7:0] io_req_data, io_rsp_data;
logic [7:0] io_req_addr;

function logic is_io(logic [15:0] addr);
    is_io = addr[15:8]==16'hc0;
endfunction

assign cpu_req_ack_o = !io_op_pending && mem_req_ack_i;
assign cpu_rsp_valid_o = io_rsp_valid || mem_rsp_valid_i;
assign cpu_rsp_data_o = io_rsp_valid ? io_rsp_data : mem_rsp_data_i;

assign mem_req_valid_o = (cpu_req_valid_i && ! is_io(cpu_req_addr_i) && ! io_op_pending) || io_mem_req;
assign mem_req_addr_o = io_mem_req ? {8'hc0, io_req_addr} : cpu_req_addr_i;
assign mem_req_data_o = cpu_req_data_i;
assign mem_req_write_o = io_mem_req ? io_req_write : cpu_req_write_i;

// BUG there is a race here, as an IO request that needs io_mem_req may come
// in at the same cycle the control CPU asks to make a change
assign ctrl_req_ack_o = ! io_mem_req;

always_ff@(posedge clock_i) begin
    // Entering IO mode
    if( cpu_req_valid_i && cpu_req_ack_o ) begin
        if( is_io(cpu_req_addr_i) ) begin
            io_op_pending <= 1'b1;
            io_req_data <= cpu_req_data_i;
            io_req_addr <= cpu_req_addr_i[7:0];
            io_req_write <= cpu_req_write_i;
        end
    end

    // Parse IO op
    if( io_op_pending && ! ctrl_intr_o && ! io_mem_req ) begin
        // an IO op should end with either direct handling, redirect to memory
        // or wait for ctrl cpu. If non of those happened, it means this is
        // the first IO cycle: parse the op
        if( io_req_write ) begin
            // Write operations ALWAYS get forwarded to the ctrl CPU (for now)
            ctrl_intr_o <= 1'b1;
        end else begin
            case( io_req_addr )
                8'h10: ctrl_intr_o <= 1'b1;                                             // Keyboard strobe
                default: io_mem_req <= 1'b1;                                            // Forward to memory by default
            endcase
        end
    end

    // Handle mem forward done
    if( io_mem_req && mem_req_ack_i ) begin
        io_mem_req <= 1'b0;
        io_op_pending <= 1'b0;
    end

    ctrl_rsp_valid_o <= 1'b0;
    io_rsp_valid <= 1'b0;
    // Handle control CPU requests
    if( ctrl_req_valid_i && ctrl_req_ack_o ) begin
        if( ctrl_req_write_i ) begin
            case( ctrl_req_addr_i )
                16'h0000: begin
                    io_rsp_data <= ctrl_req_data_i[7:0];
                    if( ctrl_intr_o ) begin
                        io_op_pending <= 1'b0;
                        ctrl_intr_o <= 1'b0;
                        if( ! io_req_write )
                            io_rsp_valid <= 1'b1;
                    end 
                end
            endcase
        end else begin
            ctrl_rsp_valid_o <= 1'b1;
            case( ctrl_req_addr_i )
                16'h0000:       ctrl_rsp_data_o <= { io_op_pending, io_req_write, io_mem_req, 13'b0, io_req_data, io_req_addr };
                default:        ctrl_rsp_data_o <= 32'hX;
            endcase
        end
    end
end

endmodule
