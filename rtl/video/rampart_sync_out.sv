`timescale 1ns/1ps
//============================================================================
//  Rampart sync outputs (sync sheet: 2F LS04, 3E/F F74, 7406 drivers).
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//      HSYNC     = NOT /HSYNC (7K pin 13)
//      VSYNC     = /VSYNC from the SOS-2, inverted and sampled by a flop
//                  on the rising edge of HSYNC, so V sync edges line up
//                  with the start of an H sync pulse
//      /COMPSYNC = NOT (HSYNC OR VSYNC): a plain OR, no serrations
//
//  The flop is modelled by an edge detect on /HSYNC in clk_sys; its new
//  value is passed straight through in the clock of the edge, so VSYNC
//  changes together with HSYNC.
//============================================================================

module rampart_sync_out (
	input  logic clk,
	input  logic hsync_n,      // 7K pin 13
	input  logic vsync_n,      // SOS-2 /VSYNC

	output logic hsync,
	output logic vsync,
	output logic csync_n
);

	/* verilator lint_off PROCASSINIT */
	logic vs_q = 1'b0;
	logic hs_d = 1'b1;
	/* verilator lint_on PROCASSINIT */

	always_ff @(posedge clk) begin
		hs_d <= hsync_n;
		if (hs_d && !hsync_n) vs_q <= ~vsync_n;
	end

	wire edge_now = hs_d & ~hsync_n;

	assign hsync   = ~hsync_n;
	assign vsync   = edge_now ? ~vsync_n : vs_q;
	assign csync_n = ~(hsync | vsync);

endmodule
