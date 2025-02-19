`timescale 1ns / 1ps

module clk_converter(
    input clk_in1,
    input reset,

    output clk_ctrl_cpu,
    output clk_ddr,
    output clk_ddr_ref,

    output clkfb_out,
    input clkfb_in,

    output locked
);

wire mmcm_locked;

MMCME2_BASE#(
    .DIVCLK_DIVIDE(4),
    .CLKFBOUT_MULT_F(48.5),
    .CLKIN1_PERIOD(20.000),     // 50MHz input clock
    .CLKOUT0_DIVIDE_F(8),       // 75.562500MHz output
    .CLKOUT1_DIVIDE(2)          // 306.250000MHz output
) mmcm(
    .CLKIN1(clk_in1),

    .CLKFBIN(clkfb_in),
    .CLKFBOUT(clkfb_out),

    .CLKOUT0(clk_ctrl_cpu),
    .CLKOUT1(clk_ddr),

    .PWRDWN(1'b0),
    .RST(reset),
    .LOCKED(mmcm_locked)
);

wire pll_clk_fb;
wire pll_locked;

PLLE2_BASE#(
    .CLKIN1_PERIOD(20.000),
    .DIVCLK_DIVIDE(1),
    .CLKFBOUT_MULT(16),
    .CLKOUT0_DIVIDE(4)  // 200MHz clock
) pll(
    .CLKFBIN(pll_clk_fb),
    .CLKFBOUT(pll_clk_fb),

    .CLKIN1(clk_in1),

    .CLKOUT0(clk_ddr_ref),

    .PWRDWN(1'b0),
    .RST(reset),
    .LOCKED(pll_locked)
);

assign locked = pll_locked && mmcm_locked;

endmodule
