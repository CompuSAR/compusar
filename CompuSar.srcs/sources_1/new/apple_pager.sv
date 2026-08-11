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

    output [31:0] mem_req_addr_o,

    sync_bus.SLAVE ctrl
);


typedef enum { MAIN, BANK_IO, BANK_D, BANKS_E_F } banks;
localparam NUM_BANKS = 4;

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
        8'hc: translate_addr=mapper[BANK_IO][write] ^ addr;
        8'hd: translate_addr=mapper[BANK_D][write] ^ addr;
        8'he: translate_addr=mapper[BANKS_E_F][write] ^ addr;
        8'hf: translate_addr=mapper[BANKS_E_F][write] ^ addr;
    endcase
endfunction

assign mem_req_addr_o = cpu_req_valid_i ? translate_addr(cpu_req_write_i, cpu_req_addr_i) : 32'hXXXXXXXX;

assign ctrl.req_ack = 1'b1;

always_ff@(posedge clock_i) begin
    ctrl.rsp_valid <= ctrl.req_valid && !ctrl.req_write;
    ctrl.rsp_data <= 32'hX;   // Reading the registers is not supported

    if( ctrl.req_valid ) begin
        if( ctrl.req_write ) begin
            case( ctrl.req_addr )
                16'h0000:       mapper[MAIN][0]         <= ctrl.req_data;
                16'h0004:       mapper[BANK_IO][0]      <= ctrl.req_data;
                16'h0008:       mapper[BANK_D][0]       <= ctrl.req_data;
                16'h000c:       mapper[BANKS_E_F][0]    <= ctrl.req_data;
                16'h0800:       mapper[MAIN][1]         <= ctrl.req_data;
                16'h0804:       mapper[BANK_IO][1]      <= ctrl.req_data;
                16'h0808:       mapper[BANK_D][1]       <= ctrl.req_data;
                16'h080c:       mapper[BANKS_E_F][1]    <= ctrl.req_data;
            endcase
        end else begin
            // CTRL CPU read request
            ctrl.rsp_data <= 32'h0;
        end
    end
end

endmodule
