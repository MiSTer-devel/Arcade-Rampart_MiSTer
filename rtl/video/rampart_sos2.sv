`timescale 1ns/1ps
//============================================================================
//  Rampart raster counters: the H count that feeds the 7K GAL and the
//  vertical side of the SOS-2 sync generator (Atari 137550-001, 11K/L).
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  Adapted from skullxbo_sos2_sync.sv of the Skull & Crossbones MiSTer core
//  (GPL-3.0): the counter structure and the 7M phase enables.
//
//  One H count is one period of the 7.159 MHz pixel clock HCLK, 8 clk_sys
//  cycles.  ce_7m marks the count boundary (HCLK rising).  HCLK is high in
//  the first half of a count and low in the second; hclk_fall marks the
//  edge between the halves.
//
//      h        0..455, 456 counts per line
//      v        0..261, advances when h wraps 455 -> 0
//      VBLANK   high on lines 240..261
//      /VSYNC   low on lines VS_START..VS_END-1 (the SOS-2 is not on any
//               published drawing; these lines are a best guess from
//               sibling boards)
//      32V      V counter bit 5
//
//  The counters free-run from power-up.  Nothing on the board resets them.
//============================================================================

module rampart_sos2 #(
	parameter int VS_START = 243,
	parameter int VS_END   = 247
)(
	input  logic       clk,
	input  logic       ce_14m,
	input  logic       ce_7m,

	output logic       hclk_fall,   // one clk_sys pulse ending the HCLK-high half
	output logic       half,        // 0 = HCLK high half of the count, 1 = low half
	output logic [8:0] h,
	output logic [8:0] v,
	output logic       vblank,
	output logic       vsync_n,
	output logic       v32
);

	/* verilator lint_off PROCASSINIT */
	logic [8:0] hc = 9'd0;
	logic [8:0] vc = 9'd0;
	logic       hf = 1'b0;
	/* verilator lint_on PROCASSINIT */

	assign hclk_fall = ce_14m & ~ce_7m;

	always_ff @(posedge clk) begin
		if (ce_7m) begin
			hf <= 1'b0;
			if (hc == 9'd455) begin
				hc <= 9'd0;
				vc <= (vc == 9'd261) ? 9'd0 : vc + 9'd1;
			end else begin
				hc <= hc + 9'd1;
			end
		end else if (hclk_fall) begin
			hf <= 1'b1;
		end
	end

	assign h       = hc;
	assign v       = vc;
	assign half    = hf;
	assign vblank  = (vc >= 9'd240);
	assign vsync_n = ~((vc >= 9'(VS_START)) && (vc < 9'(VS_END)));
	assign v32     = vc[5];

endmodule
