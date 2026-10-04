`timescale 1ns/1ps
//============================================================================
//  4L GAL 136082-1001: motion-object RAM arbiter (GAL16V8, registered).
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

module rampart_gal4l (
	input  logic        clk,
	input  logic        ce,
	input  logic [20:1] pin_i,
	output logic [20:1] pin_o
);

	/* verilator lint_off PROCASSINIT */
	logic q12 = 1'b1;
	logic q13 = 1'b1;
	logic q16 = 1'b1;
	logic q19 = 1'b1;
	/* verilator lint_on PROCASSINIT */
	logic c14;
	logic c15;
	logic c17;
	logic c18;
	logic [20:1] p;

	always_comb begin
		p = pin_i;
		p[12] = q12;
		p[13] = q13;
		p[16] = q16;
		p[19] = q19;
		p[14] = c14;
		p[15] = c15;
		p[17] = c17;
		p[18] = c18;
	end
	assign pin_o = p;

	// pin 14, combinatorial, active low
	assign c14 = ~(
		(~p[2] & ~p[4] & ~p[8] & q12 & ~q13) |
		(~p[2] & ~q12 & q13 & q19));

	// pin 15, combinatorial, active low
	assign c15 = ~(
		(p[2] & p[5] & ~p[9] & q12 & q13));

	// pin 17, combinatorial, active low
	assign c17 = ~(
		(~p[5] & ~p[6] & ~q12 & ~q13));

	// pin 18, combinatorial, active high
	assign c18 = (
		(~p[3] & ~p[5] & ~p[6] & ~p[8] & ~q19));

	always_ff @(posedge clk) begin
		if (ce) begin
			// pin 12, registered, active low
			q12 <= ~(
				(p[2] & q19) |
				(~p[2] & p[8]) |
				(~p[5] & p[7] & ~q16));
			// pin 13, registered, active low
			q13 <= ~(
				(p[2] & q16 & ~q19) |
				(~p[2] & ~p[8] & q16) |
				(~p[5] & p[7] & ~q16));
			// pin 16, registered, active high
			q16 <= (
				(~p[2] & q16) |
				(p[8]) |
				(p[2] & ~q12 & ~q13 & ~q16) |
				(p[2] & p[6] & p[9] & q12) |
				(p[2] & p[5] & p[9] & q12) |
				(p[2] & p[6] & p[9] & q13) |
				(p[2] & p[5] & p[9] & q13));
			// pin 19, registered, active high
			q19 <= (
				(p[2] & q19) |
				(~p[2] & p[8]));
		end
	end

	/* verilator lint_off UNUSEDSIGNAL */
	logic unused_ok;
	assign unused_ok = &{1'b0, pin_i};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
