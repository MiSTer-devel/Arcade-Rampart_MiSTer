`timescale 1ns/1ps
//============================================================================
//  Rampart clock-enable tree.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  Adapted from core/rtl/batman_clocks.sv of the Batman MiSTer core (GPL-3.0).
//
//  One clock domain: clk_sys = 57.272727 MHz = 4 x the 14.318181 MHz crystal.
//  Every enable is an integer divide of clk_sys:
//     ce_14m  /4   14.318181 MHz  the crystal
//     ce_7m   /8    7.159091 MHz  68000 clock and pixel clock
//     ce_3m58 /16   3.579545 MHz  YM2413
//     ce_1m19 /48   1.193182 MHz  MSM6295 (14.318181 / 12)
//  ce_14m, ce_7m and ce_3m58 decode one counter, so each slower enable is a
//  strict subset of every faster one.  ce_1m19 is also a strict subset of
//  ce_3m58 (48 is a multiple of 16).  The cycle in which an enable is high is
//  the last clk_sys cycle of its period.
//============================================================================

module rampart_clocks (
	input  logic        clk_sys,        // 57.272727 MHz

	output logic        ce_14m,
	output logic        ce_7m,
	output logic        ce_3m58,
	output logic        ce_1m19
);

	// Free-running /48 counter; every enable decodes it.  No reset: it
	// powers up at 0, which fixes the enable phase.
	/* verilator lint_off PROCASSINIT */
	logic [5:0] ce_cnt = 6'd0;
	/* verilator lint_on PROCASSINIT */
	always_ff @(posedge clk_sys) ce_cnt <= (ce_cnt == 6'd47) ? 6'd0 : ce_cnt + 6'd1;

	assign ce_14m  = (ce_cnt[1:0] == 2'd0);   // 14.318181 MHz
	assign ce_7m   = (ce_cnt[2:0] == 3'd0);   //  7.159091 MHz  CPU / PIXEL
	assign ce_3m58 = (ce_cnt[3:0] == 4'd0);   //  3.579545 MHz  YM2413
	assign ce_1m19 = (ce_cnt      == 6'd0);   //  1.193182 MHz  MSM6295

endmodule
