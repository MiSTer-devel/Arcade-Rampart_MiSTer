`timescale 1ns/1ps
//============================================================================
//  IRQ4 request: the 32V interrupt, acknowledged by a write to 0x7E6000.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  The request is a latched level: once set it stays until the /VACK strobe
//  (a write to 0x7E6000) clears it, and taking the interrupt does not clear
//  it.  The interrupt circuit itself is not on any published sheet, so two
//  schedules are provided:
//    IRQ_MODEL 0: set at the start of lines 0, 64, 128, 192 and 256 (five
//                 per frame, four of them outside VBLANK), on the pixel
//                 clock edge where the H count becomes IRQ_H of that
//                 line (IRQ_H < 0: that many counts before the line).
//                 The default, -3, lines the interrupts up with MAME's
//                 emulation of this board, the only timing reference
//                 there is: fx68k needs the request about three clocks
//                 earlier than MAME's 68000 to take it at the same
//                 instruction.  Some interrupts still land one
//                 instruction apart; no single value matches them all.
//    IRQ_MODEL 1: an LS74 whose clock is VBLANK OR NOT 32V: set when 32V
//                 falls (lines 64, 128, 192) and when VBLANK rises (240).
//  Only level 4 is used, so a pending request drives /IPL2 low and /IPL1,
//  /IPL0 high.  Board reset clears the flop.
//============================================================================

module rampart_irq #(
	parameter int IRQ_MODEL = 0,
	parameter int IRQ_H     = -3    // H count at which model 0 sets (-455..455)
) (
	input  logic       clk,
	input  logic       reset,      // board reset
	input  logic       ce_7m,
	input  logic [8:0] hpos,
	input  logic [8:0] vpos,
	input  logic       vblank,
	input  logic       vack,       // 1 while /VACK is asserted
	output logic       pending,
	output logic [2:0] ipl_n
);

	// model 0: the edge where the counters step into (line 0/64/128/192/256,
	// count IRQ_H)
	wire       wrap   = (hpos == 9'd455);
	wire [8:0] next_h = wrap ? 9'd0 : hpos + 9'd1;
	wire [8:0] next_v = !wrap ? vpos : (vpos == 9'd261) ? 9'd0 : vpos + 9'd1;
	localparam int  H_AT = (IRQ_H < 0) ? IRQ_H + 456 : IRQ_H;
	localparam bit  EARLY = (IRQ_H < 0);
	wire [8:0] line   = !EARLY ? next_v : (next_v == 9'd261) ? 9'd0 : next_v + 9'd1;
	wire set0 = ce_7m && (next_h == 9'(H_AT)) && (line[4:0] == 5'd0) && !line[5];

	// model 1: rising edge of VBLANK OR NOT 32V
	wire ck1 = vblank | ~vpos[5];
	logic ck1_d;
	always_ff @(posedge clk) ck1_d <= ck1;
	wire set1 = ck1 && !ck1_d;

	wire set = (IRQ_MODEL == 1) ? set1 : set0;

	always_ff @(posedge clk) begin
		if (reset || vack) pending <= 1'b0;
		else if (set)      pending <= 1'b1;
	end

	assign ipl_n = pending ? 3'b011 : 3'b111;

	/* verilator lint_off UNUSEDSIGNAL */
	wire _unused = &{1'b0, line[8:6], 1'b0};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
