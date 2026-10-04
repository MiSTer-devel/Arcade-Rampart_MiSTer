`timescale 1ns/1ps
//============================================================================
//  Output latches at 0x640000: 7B 74LS273 (D15-8) and 6C 74LS174 (D5-0).
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  Both latches are clocked by /LATCH = R/W OR /PARALEL, with no data-strobe
//  qualification, so every write to 0x640000 (A1 ignored) loads both bytes:
//  a byte write loads the byte the 68000 replicates onto the other lane.
//  They load on the rising edge of /LATCH, at the end of the write cycle.
//  Board /RESET clears both.
//     15 VCR (jumper, not fitted)   14 -            13 LETA 13A TEST
//     12 CBANK                      11 LETA 12A TEST 10 LETA RESOL
//      9 coin counter L              8 coin counter R
//      7, 6 not latched (6C has six bits)
//      5 PMIX0 (OKI gain)            4 /PCMRES (MSM6295 reset, level)
//      3-1 YMIX2-0 (YM gain)         0 /YAMRES (YM2413 /IC, level)
//============================================================================

module rampart_latch (
	input  logic        clk,
	input  logic        reset,      // board reset
	input  logic        wr,         // 1-clk pulse: /LATCH rising edge
	input  logic [15:0] d,
	output logic [15:0] q
);

	always_ff @(posedge clk) begin
		if (reset) begin
			q <= 16'h0000;
		end else if (wr) begin
			q[15:8] <= d[15:8];
			q[5:0]  <= d[5:0];
		end
		q[7:6] <= 2'b00;
	end

	/* verilator lint_off UNUSEDSIGNAL */
	wire _unused = &{1'b0, d[7:6], 1'b0};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
