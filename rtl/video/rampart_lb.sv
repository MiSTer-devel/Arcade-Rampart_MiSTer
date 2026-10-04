`timescale 1ns/1ps
//============================================================================
//  Rampart motion-object line buffer: the Lb custom 137536-001 at 1F/H.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  Adapted from batman_lb.sv of the Batman MiSTer core (GPL-3.0), itself
//  after skullxbo_lb.sv of the Skull & Crossbones core.
//
//  Two banks of 512 x 8 bits, {COLOUR, pen}.  The MOB writes one bank while
//  the display reads the other; the banks swap once per line.  Pen 0 is
//  empty, so a cleared location is transparent.
//
//  Read side: rd_ce once per displayed pixel at address ra.  The location
//  is cleared one clock after it is read, so the bank is empty again when
//  the MOB next writes it.  q is valid from the clock after rd_ce until
//  the next rd_ce.
//
//  FIRST_WINS = 0: every opaque write lands, so the last object in the list
//  ends up on top.  FIRST_WINS = 1: a write is dropped where an opaque pixel
//  is already stored, so the first object wins.  Which one the chip does is
//  not known; 0 matches MAME.
//============================================================================

module rampart_lb #(
	parameter bit FIRST_WINS = 1'b0
)(
	input  logic       clk,
	input  logic       reset,

	input  logic       wbank,        // the bank the MOB writes

	input  logic       we,
	input  logic [8:0] wa,
	input  logic [7:0] wd,

	input  logic       rd_ce,
	input  logic [8:0] ra,
	output logic [7:0] q
);

	localparam logic [7:0] EMPTY = 8'd0;

	logic [7:0] mem0 [0:511];
	logic [7:0] mem1 [0:511];

	// One write-side stage reads the target location before the write.
	// The MOB never writes on consecutive clocks when paced at 14 MHz; at
	// clk_sys rate FIRST_WINS would need forwarding, so it is not used there.
	logic       we_d, wbank_d;
	logic [8:0] wa_d;
	logic [7:0] wd_d;
	logic [7:0] occ;

	logic [8:0] ra_d;
	logic       rd_d, ers;

	always_ff @(posedge clk) begin
		if (reset) begin
			we_d <= 1'b0;
			rd_d <= 1'b0;
			ers  <= 1'b0;
		end else begin
			we_d    <= we;
			wa_d    <= wa;
			wd_d    <= wd;
			wbank_d <= wbank;
			rd_d    <= rd_ce;
			ers     <= rd_ce;
			if (rd_ce) ra_d <= ra;
		end
	end

	wire wr_ok = we_d && (wd_d[3:0] != 4'h0) && (!FIRST_WINS || (occ[3:0] == 4'h0));

	wire [8:0] a0_rd = (wbank   == 1'b0) ? wa   : ra;
	wire [8:0] a1_rd = (wbank   == 1'b1) ? wa   : ra;
	wire [8:0] a0_wr = (wbank_d == 1'b0) ? wa_d : ra_d;
	wire [8:0] a1_wr = (wbank_d == 1'b1) ? wa_d : ra_d;
	wire       e0_wr = (wbank_d == 1'b0) ? wr_ok : ers;
	wire       e1_wr = (wbank_d == 1'b1) ? wr_ok : ers;
	wire [7:0] d0_wr = (wbank_d == 1'b0) ? wd_d : EMPTY;
	wire [7:0] d1_wr = (wbank_d == 1'b1) ? wd_d : EMPTY;

	logic [7:0] q0, q1;
	always_ff @(posedge clk) begin
		q0 <= mem0[a0_rd];
		if (e0_wr) mem0[a0_wr] <= d0_wr;
	end
	always_ff @(posedge clk) begin
		q1 <= mem1[a1_rd];
		if (e1_wr) mem1[a1_wr] <= d1_wr;
	end

	assign occ = wbank_d ? q1 : q0;

	// hold the read value past the erase
	logic [7:0] q_hold;
	always_ff @(posedge clk) if (rd_d) q_hold <= wbank_d ? q0 : q1;
	assign q = q_hold;

	/* verilator lint_off UNUSEDSIGNAL */
	wire unused_occ = &{1'b0, occ[7:4]};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
