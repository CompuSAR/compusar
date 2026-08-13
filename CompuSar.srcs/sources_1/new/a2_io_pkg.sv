`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/12/2026 09:59:07 PM
// Design Name: 
// Module Name: a2_io_pkg
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

package a2_io;
    typedef enum {
        Mem,
        Diskette
    } Peripheral;

    localparam NumPeripherals = 2; // Needs to be the same as Peripheral.num()
endpackage