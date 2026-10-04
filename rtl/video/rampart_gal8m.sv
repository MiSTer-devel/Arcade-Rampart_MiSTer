`timescale 1ns/1ps
//============================================================================
//  8M GAL 136082-1004: motion-object RAM address mux (GAL20V8).
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

module rampart_gal8m (
	input  logic        clk,
	input  logic        ce,
	input  logic [24:1] pin_i,
	output logic [24:1] pin_o
);

	logic c15;
	logic c16;
	logic c17;
	logic c18;
	logic c19;
	logic c20;
	logic c22;
	logic [24:1] p;

	always_comb begin
		p = pin_i;
		p[15] = c15;
		p[16] = c16;
		p[17] = c17;
		p[18] = c18;
		p[19] = c19;
		p[20] = c20;
		p[22] = c22;
	end
	assign pin_o = p;

	// pin 15, combinatorial, active high
	assign c15 = (
		(p[1] & ~p[2] & p[10]) |
		(~p[1] & ~p[2] & p[3]));

	// pin 16, combinatorial, active high
	assign c16 = (
		(p[2]) |
		(p[1] & p[11]) |
		(~p[1] & p[4]));

	// pin 17, combinatorial, active high
	assign c17 = (
		(p[2]) |
		(p[1] & p[13]) |
		(~p[1] & p[5]));

	// pin 18, combinatorial, active high
	assign c18 = (
		(p[2]) |
		(p[1] & p[14]) |
		(~p[1] & p[6]));

	// pin 19, combinatorial, active high
	assign c19 = (
		(p[2]) |
		(p[1] & p[23]) |
		(~p[1] & p[7]));

	// pin 20, combinatorial, active high
	assign c20 = (
		(p[2]) |
		(p[1] & p[21]) |
		(~p[1] & p[8]));

	// pin 22, combinatorial, active high
	assign c22 = (
		(p[2]) |
		(~p[1] & p[9]));

	/* verilator lint_off UNUSEDSIGNAL */
	logic unused_ok;
	assign unused_ok = &{1'b0, clk, ce, pin_i};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
