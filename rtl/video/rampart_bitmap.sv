`timescale 1ns/1ps
//============================================================================
//  Rampart bitmap playfield: 128 KB of video DRAM (four 4464s, 8H-11H), the
//  raster fetch and the pixel shifter.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  Organisation.  64K words; line y is DRAM row y (CPU A16..A9) and word k
//  of the line (CPU A8..A1) holds pixel 2k in bits 15-8 and pixel 2k+1 in
//  bits 7-0.  One line is one DRAM page.
//
//  Raster fetch.  The 8J sequencer reads the line in page mode, four words
//  (eight pixels) per group of eight H counts, into a word latch.  Group
//  g = h[8:3] reads words 4g..4g+3 of row v.  At the end of the group the
//  latch moves to the shifter, which puts out one pixel per count during
//  the next group.  So pixel p leaves the shifter during count p + 8 and,
//  after the colour RAM stage, reaches the DAC during count p + 9.
//
//  CPU side.  Word and byte access through a second RAM port.  The fetch
//  never blocks it here.  WAIT_MODEL = 1 adds the board's slot timing: the
//  8J GAL (clocked at 14 MHz) holds the CPU until its one slot per group
//  while the raster fetches (8J pin 11 = 7K pin 15 low), and releases it at
//  once in the fetch-free window.  WAIT_MODEL = 0 never waits.
//============================================================================

module rampart_bitmap #(
	parameter int WAIT_MODEL  = 0
)(
	input  logic        clk,
	input  logic        ce_14m,
	input  logic        ce_7m,
	input  logic        half,         // 0 = HCLK high half
	input  logic  [8:0] h,
	input  logic  [8:0] v,
	input  logic        fetch_off,    // 7K pin 15

	// CPU port
	input  logic [16:1] cpu_a,
	input  logic [15:0] cpu_din,
	output logic [15:0] cpu_dout,
	input  logic        cpu_rw,
	input  logic        cpu_uds_n,
	input  logic        cpu_lds_n,
	input  logic        bmsel_n,      // includes /AS
	output logic        cpu_wait,     // 1 = hold DTACK

	// video
	output logic  [7:0] pf_pix
);

	// ---- the DRAM, one RAM per byte lane ----------------------------------
	logic [7:0] ram_hi [0:65535];
	logic [7:0] ram_lo [0:65535];

	wire        cpu_wr_hi = ~bmsel_n & ~cpu_rw & ~cpu_uds_n;
	wire        cpu_wr_lo = ~bmsel_n & ~cpu_rw & ~cpu_lds_n;

	always_ff @(posedge clk) begin
		if (cpu_wr_hi) begin
			ram_hi[cpu_a]  <= cpu_din[15:8];
			cpu_dout[15:8] <= cpu_din[15:8];
		end else begin
			cpu_dout[15:8] <= ram_hi[cpu_a];
		end
	end
	always_ff @(posedge clk) begin
		if (cpu_wr_lo) begin
			ram_lo[cpu_a] <= cpu_din[7:0];
			cpu_dout[7:0] <= cpu_din[7:0];
		end else begin
			cpu_dout[7:0] <= ram_lo[cpu_a];
		end
	end

	// ---- raster fetch -------------------------------------------------------
	// Word j of the group is read during count 4 + j of the group.
	logic [15:0] vid_q;
	wire   [7:0] col = {h[8:3], h[1:0]};
	wire  [15:0] vid_a = {v[7:0], col};

	always_ff @(posedge clk) begin
		vid_q[15:8] <= ram_hi[vid_a];
		vid_q[7:0]  <= ram_lo[vid_a];
	end

	logic [47:0] latch;       // words 0-2 of the page latch; word 3 goes straight in
	logic [63:0] shifter;

	always_ff @(posedge clk) begin
		if (ce_7m) begin
			if (h[2]) begin
				case (h[1:0])
					2'd0: latch[47:32] <= vid_q;
					2'd1: latch[31:16] <= vid_q;
					2'd2: latch[15:0]  <= vid_q;
					default: ;
				endcase
			end
			if (h[2:0] == 3'd7) shifter <= {latch, vid_q};
		end
	end

	// Pixel i of the group is on the shifter output during count i.
	always_comb begin
		case (h[2:0])
			3'd0: pf_pix = shifter[63:56];
			3'd1: pf_pix = shifter[55:48];
			3'd2: pf_pix = shifter[47:40];
			3'd3: pf_pix = shifter[39:32];
			3'd4: pf_pix = shifter[31:24];
			3'd5: pf_pix = shifter[23:16];
			3'd6: pf_pix = shifter[15:8];
			default: pf_pix = shifter[7:0];
		endcase
	end

	// ---- CPU slot (WAIT_MODEL = 1) ------------------------------------------
	generate
		if (WAIT_MODEL == 1) begin : g_wait
			logic [24:1] pin_i, pin_o;
			always_comb begin
				pin_i     = '0;
				pin_i[2]  = bmsel_n;
				pin_i[3]  = ~cpu_rw;
				pin_i[4]  = cpu_uds_n;
				pin_i[5]  = cpu_lds_n;
				pin_i[6]  = ~half;       // HCLK
				pin_i[7]  = h[0];        // 1H
				pin_i[8]  = h[1];        // 2H
				pin_i[9]  = h[2];        // 4H
				pin_i[11] = fetch_off;
				pin_i[14] = 1'b0;        // guard input, not modelled
			end
			rampart_gal8j u_8j (.clk(clk), .ce(ce_14m), .pin_i(pin_i), .pin_o(pin_o));
			assign cpu_wait = ~bmsel_n & ~pin_o[20];
			/* verilator lint_off UNUSEDSIGNAL */
			wire unused_8j = &{1'b0, pin_o[24:21], pin_o[19:1]};
			/* verilator lint_on UNUSEDSIGNAL */
		end else begin : g_nowait
			assign cpu_wait = 1'b0;
			/* verilator lint_off UNUSEDSIGNAL */
			wire unused_w = &{1'b0, ce_14m, half, fetch_off};
			/* verilator lint_on UNUSEDSIGNAL */
		end
	endgenerate

	/* verilator lint_off UNUSEDSIGNAL */
	wire unused_v = v[8];
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
