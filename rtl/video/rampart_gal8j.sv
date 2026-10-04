`timescale 1ns/1ps
//============================================================================
//  8J GAL 136082-1003: bitmap DRAM sequencer (GAL20V8, registered).
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  Generated from the chip's fuse map (jedutil -view), one assign per
//  output, terms in the fuse-map order.  pin_i carries the levels on the
//  input pins; pin_o carries every pin as the board sees it (outputs from
//  the GAL, inputs passed through).  Registered pins power up high and load
//  on the clock edge marked by ce.  The /OE pin is taken as tied low.
//  Do not edit by hand.
//============================================================================

module rampart_gal8j (
	input  logic        clk,
	input  logic        ce,
	input  logic [24:1] pin_i,
	output logic [24:1] pin_o
);

	/* verilator lint_off PROCASSINIT */
	logic q15 = 1'b1;
	logic q16 = 1'b1;
	logic q17 = 1'b1;
	logic q18 = 1'b1;
	logic q19 = 1'b1;
	logic q22 = 1'b1;
	/* verilator lint_on PROCASSINIT */
	logic c20;
	logic c21;
	logic [24:1] p;

	always_comb begin
		p = pin_i;
		p[15] = q15;
		p[16] = q16;
		p[17] = q17;
		p[18] = q18;
		p[19] = q19;
		p[22] = q22;
		p[20] = c20;
		p[21] = c21;
	end
	assign pin_o = p;

	// pin 20, combinatorial, active low
	assign c20 = ~(
		(~p[2] & p[11] & p[14]) |
		(~p[2] & ~p[6] & ~p[11]) |
		(~p[2] & p[7] & ~p[11]) |
		(~p[2] & p[8] & ~p[11]) |
		(~p[2] & p[9] & ~p[11]));

	// pin 21, combinatorial, active high
	assign c21 = (
		1'b0);

	always_ff @(posedge clk) begin
		if (ce) begin
			// pin 15, registered, active low
			q15 <= ~(
				(~p[2] & p[6] & p[11] & ~q16) |
				(~p[2] & p[6] & p[7] & ~p[8] & ~p[9] & ~q16) |
				(~p[6] & p[9] & ~p[11]));
			// pin 16, registered, active low
			q16 <= ~(
				(~p[2] & p[11] & q15 & ~q16) |
				(~p[2] & p[6] & p[11] & ~p[14] & q15) |
				(p[7] & ~p[8] & ~p[11] & ~q16) |
				(~p[2] & p[6] & ~p[7] & ~p[8] & ~p[11]) |
				(~p[6] & p[9] & ~p[11]) |
				(~p[7] & p[9] & ~p[11]) |
				(~p[8] & p[9] & ~p[11]) |
				(p[7] & p[8] & ~p[9] & ~p[11]));
			// pin 17, registered, active high
			q17 <= (
				(p[11] & ~q16) |
				(p[6] & p[7] & ~p[11]) |
				(p[9] & ~p[11]) |
				(p[7] & ~p[8] & ~p[11]));
			// pin 18, registered, active high
			q18 <= (
				(p[11] & ~q16) |
				(p[11] & q15) |
				(~p[8] & ~p[9] & ~p[11]));
			// pin 19, registered, active low
			q19 <= ~(
				(~p[2] & p[7] & ~p[8] & ~p[9] & ~p[11] & ~q16) |
				(~p[2] & p[11] & q15 & ~q16));
			// pin 22, registered, active low
			q22 <= ~(
				(~p[2] & p[3] & ~p[4] & p[7] & ~p[8] & ~p[9] & ~p[11] & ~q16) |
				(~p[2] & p[3] & ~p[5] & p[7] & ~p[8] & ~p[9] & ~p[11] & ~q16) |
				(~p[2] & p[3] & ~p[4] & p[11] & q15 & ~q16) |
				(~p[2] & p[3] & ~p[5] & p[11] & q15 & ~q16));
		end
	end

	/* verilator lint_off UNUSEDSIGNAL */
	logic unused_ok;
	assign unused_ok = &{1'b0, pin_i};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
