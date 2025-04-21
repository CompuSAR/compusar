`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/28/2024 08:34:24 PM
// Design Name: 
// Module Name: apple_pager
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


module apple_pager(
    input clock_i,

    input cpu_req_valid_i,
    output logic cpu_req_ack_o,
    input cpu_req_write_i,
    input [15:0] cpu_req_addr_i,
    input [7:0] cpu_req_data_i,

    output cpu_rsp_valid_o,
    output [7:0] cpu_rsp_data_o,

    output logic mem_req_valid_o,
    output logic[31:0] mem_req_addr_o,
    output mem_req_write_o,
    output [7:0] mem_req_data_o,
    input mem_req_ack_i,

    input mem_rsp_valid_i,
    input [7:0] mem_rsp_data_i,

    input ctrl_req_valid_i,
    input ctrl_req_write_i,
    input [15:0] ctrl_req_addr_i,
    input [31:0] ctrl_req_data_i,
    output ctrl_req_ack_o,

    output logic ctrl_rsp_valid_o,
    output logic[31:0] ctrl_rsp_data_o,

    output ctrl_intr_o
    );


typedef enum { MAIN, BANK_D, BANKS_E_F } banks;
localparam NUM_BANKS = 3;

    /* map1 0000-1ff, W: c008 main c009 aux
    *  d000-dfff - ROM/LC bank1/LC bank2
    *  e000-ffff - ROM/LC
    */
logic [31:0] mapper[NUM_BANKS][2];

logic io_cmd_pending = 1'b0;
logic [15:0] io_cmd_addr;
logic io_cmd_write;
logic [7:0] io_cmd_write_data;
logic io_rsp_valid = 1'b0;
logic [7:0] io_rsp_data;

assign ctrl_intr_o = io_cmd_pending;

assign mem_req_write_o = cpu_req_write_i;
assign mem_req_data_o = cpu_req_data_i;

assign cpu_rsp_valid_o = !io_cmd_pending && mem_rsp_valid_i || io_rsp_valid;
assign cpu_rsp_data_o = io_cmd_pending ? io_rsp_data : mem_rsp_data_i;

function logic is_io(logic [15:0] addr);
    is_io = addr[15:12]==8'hc;
endfunction

function logic[31:0] translate_addr(logic write, logic [15:0] addr);
    case( addr[15:12] )
        8'h0: translate_addr=mapper[MAIN][write] ^ addr;
        8'h1: translate_addr=mapper[MAIN][write] ^ addr;
        8'h2: translate_addr=mapper[MAIN][write] ^ addr;
        8'h3: translate_addr=mapper[MAIN][write] ^ addr;
        8'h4: translate_addr=mapper[MAIN][write] ^ addr;
        8'h5: translate_addr=mapper[MAIN][write] ^ addr;
        8'h6: translate_addr=mapper[MAIN][write] ^ addr;
        8'h7: translate_addr=mapper[MAIN][write] ^ addr;
        8'h8: translate_addr=mapper[MAIN][write] ^ addr;
        8'h9: translate_addr=mapper[MAIN][write] ^ addr;
        8'ha: translate_addr=mapper[MAIN][write] ^ addr;
        8'hb: translate_addr=mapper[MAIN][write] ^ addr;
        8'hc: translate_addr=32'hXXXXXXXX;
        8'hd: translate_addr=mapper[BANK_D][write] ^ addr;
        8'he: translate_addr=mapper[BANKS_E_F][write] ^ addr;
        8'hf: translate_addr=mapper[BANKS_E_F][write] ^ addr;
    endcase
endfunction

always_comb begin
    cpu_req_ack_o = 1'b0;

    if( is_io(cpu_req_addr_i) ) begin
        cpu_req_ack_o = !io_cmd_pending;
    end else begin
        cpu_req_ack_o = !io_cmd_pending && mem_req_ack_i;
    end
end

always_comb begin
    mem_req_addr_o = 32'hX;
    mem_req_valid_o = 1'b0;

    if( cpu_req_valid_i && cpu_req_ack_o ) begin
        mem_req_addr_o = translate_addr(cpu_req_write_i, cpu_req_addr_i);

        if( ! is_io(mem_req_addr_o) ) begin
            mem_req_valid_o = !io_cmd_pending;
        end
    end
end

assign ctrl_req_ack_o = 1'b1;

always_ff@(posedge clock_i) begin
    ctrl_rsp_valid_o <= ctrl_req_valid_i && !ctrl_req_write_i;
    ctrl_rsp_data_o <= 32'hX;   // Reading the registers is not supported

    io_rsp_valid <= 1'b0;

    if( ctrl_req_valid_i ) begin
        if( ctrl_req_write_i ) begin
            case( ctrl_req_addr_i )
                16'h0000:       mapper[MAIN][0]         <= ctrl_req_data_i;
                16'h0004:       mapper[BANK_D][0]       <= ctrl_req_data_i;
                16'h0008:       mapper[BANKS_E_F][0]    <= ctrl_req_data_i;
                16'h000c:       mapper[MAIN][1]         <= ctrl_req_data_i;
                16'h0010:       mapper[BANK_D][1]       <= ctrl_req_data_i;
                16'h0014:       mapper[BANKS_E_F][1]    <= ctrl_req_data_i;

                16'h0080:       begin
                    io_rsp_data <= ctrl_req_data_i[7:0];
                    io_rsp_valid <= io_cmd_pending && !io_cmd_write;
                    io_cmd_pending <= 1'b0;
                end
            endcase
        end else begin
            // CTRL CPU read request
            case( ctrl_req_addr_i )
                16'h0080:       begin
                    ctrl_rsp_data_o <= { io_cmd_pending, io_cmd_write, 6'b000000, io_cmd_write_data, io_cmd_addr };
                end
            endcase
        end
    end

    if( cpu_req_valid_i && cpu_req_ack_o && is_io(cpu_req_addr_i) ) begin
        io_cmd_pending <= 1'b1;
        io_cmd_addr <= cpu_req_addr_i;
        io_cmd_write <= cpu_req_write_i;
        io_cmd_write_data <= cpu_req_data_i;
    end
end

endmodule
