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
    input cpu_req_write_i,
    input [15:0] cpu_req_addr_i,

    output logic[31:0] mem_req_addr_o,

    input ctrl_req_valid_i,
    input ctrl_req_write_i,
    input [15:0] ctrl_req_addr_i,
    input [31:0] ctrl_req_data_i,
    output ctrl_req_ack_o,

    output logic ctrl_rsp_valid_o,
    output logic[31:0] ctrl_rsp_data_o
    );


typedef enum { MAIN, BANK_D, BANKS_E_F } banks;
localparam NUM_BANKS = 3;

    /* map1 0000-1ff, W: c008 main c009 aux
    *  d000-dfff - ROM/LC bank1/LC bank2
    *  e000-ffff - ROM/LC
    */
logic [31:0] mapper[NUM_BANKS][2];

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
        8'hc: translate_addr=mapper[MAIN][write] ^ addr;
        8'hd: translate_addr=mapper[BANK_D][write] ^ addr;
        8'he: translate_addr=mapper[BANKS_E_F][write] ^ addr;
        8'hf: translate_addr=mapper[BANKS_E_F][write] ^ addr;
    endcase
endfunction

always_comb begin
    mem_req_addr_o = 32'hX;

    if( cpu_req_valid_i ) begin
        mem_req_addr_o = translate_addr(cpu_req_write_i, cpu_req_addr_i);
    end
end

assign ctrl_req_ack_o = 1'b1;

always_ff@(posedge clock_i) begin
    ctrl_rsp_valid_o <= ctrl_req_valid_i && !ctrl_req_write_i;
    ctrl_rsp_data_o <= 32'hX;   // Reading the registers is not supported

    if( ctrl_req_valid_i ) begin
        if( ctrl_req_write_i ) begin
            case( ctrl_req_addr_i )
                MAIN:                           mapper[MAIN][0]         <= ctrl_req_data_i;
                BANK_D:                         mapper[BANK_D][0]       <= ctrl_req_data_i;
                BANKS_E_F:                      mapper[BANKS_E_F][0]    <= ctrl_req_data_i;
                MAIN + NUM_BANKS:               mapper[MAIN][1]         <= ctrl_req_data_i;
                BANK_D + NUM_BANKS:             mapper[BANK_D][1]       <= ctrl_req_data_i;
                BANKS_E_F + NUM_BANKS:          mapper[BANKS_E_F][1]    <= ctrl_req_data_i;
            endcase
        end
    end
end

endmodule
