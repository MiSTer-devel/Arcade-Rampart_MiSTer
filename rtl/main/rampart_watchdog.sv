`timescale 1ns/1ps
//============================================================================
//  Reset counter and watchdog: the 74LS197 at 7D.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  The two LS197 sections are cascaded into one 4-bit counter clocked by the
//  falling edge of VBLANK.  Its QD output is the board /RESET.
//    * /CLR (power-on RC or the reset jumper) clears it to 0: /RESET low.
//      Eight VBLANK falling edges later the count reaches 8 and /RESET
//      rises, so power-on reset lasts about eight frames.
//    * /LD loads 8 (the data inputs are wired 1000).  It is driven by the
//      /WDOG strobe ANDed with the watchdog-disable jumper node, so any
//      read or write of 0x726000 pets the watchdog.  /LD is asynchronous
//      and level-sensitive: the count sits at 8 while /WDOG is low.
//    * With no pet, eight VBLANK falls take the count 8 -> 15 -> 0: /RESET
//      asserts.  Eight more take it back to 8 and release it, so a bite
//      holds the board in reset for eight frames.
//    * The disable jumper holds /LD low: the count stays at 8 and the
//      watchdog never bites.
//  FAST_BOOT = 1 (simulation only) loads 8 as soon as power-on ends, so
//  /RESET follows power_on with no eight-frame hold and a simulation can release
//  the CPU at any raster position.
//============================================================================

module rampart_watchdog #(
	parameter bit FAST_BOOT = 1'b0
) (
	input  logic clk,
	input  logic power_on,      // active high: /CLR
	input  logic jmp1,          // 1 = watchdog-disable jumper fitted
	input  logic wdog,          // 1 while /WDOG is asserted
	input  logic vblank,
	output logic board_reset,   // 1 = /RESET asserted (QD low)
	output logic [3:0] count    // for observation
);

	logic vblank_d, power_on_d;
	always_ff @(posedge clk) begin
		vblank_d   <= vblank;
		power_on_d <= power_on;
		if (power_on)            count <= 4'd0;
		else if (wdog || jmp1 || (FAST_BOOT && power_on_d)) count <= 4'd8;
		else if (vblank_d && !vblank) count <= count + 4'd1;
	end

	assign board_reset = ~count[3];

endmodule
