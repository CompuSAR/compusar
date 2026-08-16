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


typedef enum { MAIN, BANK_IO, BANK_D, BANKS_E_F, DEVNULL } banks;
localparam NUM_BANKS = 5;

    /* map1 0000-1ff, W: c008 main c009 aux
    *  d000-dfff - ROM/LC bank1/LC bank2
    *  e000-ffff - ROM/LC
    */
logic [31:0] mapper[NUM_BANKS][2];
logic [31:0] slot_roms[7:0];

function logic[31:0] translate_io(input logic write, input logic [15:0] addr);
    automatic logic[7:0] slot = addr[11:8];

    if( slot==4'h0 )
        translate_io=mapper[BANK_IO][write];
    else if( write )
        translate_io=0;
    else
        translate_io=slot_roms[slot[2:0]];
endfunction

function logic[31:0] translate_addr(input logic write, input logic [15:0] addr);
    automatic logic [31:0] addr_mask;
    case( addr[15:12] )
        8'h0: addr_mask = mapper[MAIN][write];
        8'h1: addr_mask = mapper[MAIN][write];
        8'h2: addr_mask = mapper[MAIN][write];
        8'h3: addr_mask = mapper[MAIN][write];
        8'h4: addr_mask = mapper[MAIN][write];
        8'h5: addr_mask = mapper[MAIN][write];
        8'h6: addr_mask = mapper[MAIN][write];
        8'h7: addr_mask = mapper[MAIN][write];
        8'h8: addr_mask = mapper[MAIN][write];
        8'h9: addr_mask = mapper[MAIN][write];
        8'ha: addr_mask = mapper[MAIN][write];
        8'hb: addr_mask = mapper[MAIN][write];
        8'hc: addr_mask = translate_io(write, addr);
        8'hd: addr_mask = mapper[BANK_D][write];
        8'he: addr_mask = mapper[BANKS_E_F][write];
        8'hf: addr_mask = mapper[BANKS_E_F][write];
    endcase

    // If the map is empty, direct it to the same place
    if( addr_mask==0 )
        translate_addr = mapper[DEVNULL][write];
    else
        translate_addr = addr ^ addr_mask;
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
                16'h0010:       mapper[DEVNULL][0]      <= ctrl.req_data;
                16'h0100:       slot_roms[0]            <= ctrl.req_data;
                16'h0110:       slot_roms[1]            <= ctrl.req_data;
                16'h0120:       slot_roms[2]            <= ctrl.req_data;
                16'h0130:       slot_roms[3]            <= ctrl.req_data;
                16'h0140:       slot_roms[4]            <= ctrl.req_data;
                16'h0150:       slot_roms[5]            <= ctrl.req_data;
                16'h0160:       slot_roms[6]            <= ctrl.req_data;
                16'h0170:       slot_roms[7]            <= ctrl.req_data;
                16'h0800:       mapper[MAIN][1]         <= ctrl.req_data;
                16'h0804:       mapper[BANK_IO][1]      <= ctrl.req_data;
                16'h0808:       mapper[BANK_D][1]       <= ctrl.req_data;
                16'h080c:       mapper[BANKS_E_F][1]    <= ctrl.req_data;
                16'h0810:       mapper[DEVNULL][1]      <= ctrl.req_data;
            endcase
        end else begin
            // CTRL CPU read request
            ctrl.rsp_data <= 32'h0;
        end
    end
end

endmodule
