`timescale 1ns/1ps
//============================================================================
//  7K GAL 136082-1002: horizontal timing decode (GAL16V8, registered).
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

module rampart_gal7k (
	input  logic        clk,
	input  logic        ce,
	input  logic [20:1] pin_i,
	output logic [20:1] pin_o
);

	/* verilator lint_off PROCASSINIT */
	logic q12 = 1'b1;
	logic q14 = 1'b1;
	logic q15 = 1'b1;
	logic q16 = 1'b1;
	logic q17 = 1'b1;
	logic q18 = 1'b1;
	/* verilator lint_on PROCASSINIT */
	logic c13;
	logic [20:1] p;

	always_comb begin
		p = pin_i;
		p[12] = q12;
		p[14] = q14;
		p[15] = q15;
		p[16] = q16;
		p[17] = q17;
		p[18] = q18;
		p[13] = c13;
	end
	assign pin_o = p;

	// pin 13, combinatorial, active low
	assign c13 = ~(
		(~p[5] & ~p[7] & ~p[8] & p[9] & p[19]) |
		(~p[6] & ~p[7] & ~p[8] & p[9] & p[19]) |
		(p[4] & p[5] & p[6] & p[7] & p[8] & ~p[9] & p[19]));

	always_ff @(posedge clk) begin
		if (ce) begin
			// pin 12, registered, active high
			q12 <= (
				(~p[4] & ~p[6] & ~p[7] & ~p[8] & ~p[9] & ~p[19]) |
				(~p[5] & ~p[6] & ~p[7] & ~p[8] & ~p[9] & ~p[19]) |
				(~p[5] & ~p[6] & ~p[7] & p[9] & p[19]) |
				(~p[8] & p[9] & p[19]) |
				(p[4] & p[5] & p[6] & p[8] & ~p[9] & p[19]) |
				(p[7] & p[8] & ~p[9] & p[19]));
			// pin 14, registered, active high
			q14 <= (
				(p[3] & ~p[5] & ~p[6] & ~p[7] & p[8] & p[9] & p[19]) |
				(p[4] & ~p[5] & ~p[6] & ~p[7] & p[8] & p[9] & p[19]));
			// pin 15, registered, active high
			q15 <= (
				(~p[3] & ~p[4] & ~p[5] & ~p[6] & ~p[7] & p[9] & p[19]) |
				(~p[8] & p[9] & p[19]) |
				(p[4] & p[5] & p[6] & p[8] & ~p[9] & p[19]) |
				(p[7] & p[8] & ~p[9] & p[19]));
			// pin 16, registered, active low
			q16 <= ~(
				(p[2] & ~p[3] & ~p[4] & p[5] & ~p[6] & ~p[7] & ~p[8] & ~p[9] & ~p[19]));
			// pin 17, registered, active high
			q17 <= (
				(p[2] & ~p[3] & p[4] & ~p[5] & ~p[6] & ~p[7] & p[8] & p[9] & p[19]));
			// pin 18, registered, active low
			q18 <= ~(
				(~p[5] & ~p[6] & ~p[7] & ~p[8] & ~p[9] & ~p[19]) |
				(p[3] & p[4] & ~p[5] & ~p[6] & ~p[7] & p[8] & p[9] & p[19]));
		end
	end

	/* verilator lint_off UNUSEDSIGNAL */
	logic unused_ok;
	assign unused_ok = &{1'b0, pin_i};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
