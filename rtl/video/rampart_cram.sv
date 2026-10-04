`timescale 1ns/1ps
//============================================================================
//  Rampart colour RAM (4H, 2K x 8) and the pixel latches 5H, 6H and 7H.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  The byte-wide RAM with a bank bit on an address pin follows
//  klax_palette.v of the Klax MiSTer core (GPL-2.0-or-later).
//
//  The CPU reaches the RAM on D15-8 only.  CPU byte k (0x3C0000 + 2k, k =
//  A10..A1) is RAM address {CBANK, k}; colour n is the byte pair 2n (high)
//  and 2n+1 (low), an IRGB 1555 word.
//
//  The video side reads each pixel's colour in two halves of the pixel
//  clock: the high byte while HCLK is high (5H latches it when HCLK falls),
//  then the low byte; on the next HCLK rise 6H takes 5H and 7H takes the
//  RAM, so {6H, 7H} is the colour word for one count.  /BLANK clears 6H and
//  7H, which forces all three guns to black.
//
//  CPU_STEAL = 1 (default): while the CPU selects the colour RAM, the
//  address mux gives the RAM to the CPU, so the video side latches the byte
//  at the CPU's address (on a write, the byte being written) instead of the
//  pixel's.  The game writes the palette in vertical blank, so this does
//  not show in normal play.  0 gives the video side its own port.
//============================================================================

module rampart_cram #(
	parameter bit CPU_STEAL = 1'b1
)(
	input  logic        clk,
	input  logic        ce_7m,
	input  logic        hclk_fall,
	input  logic        half,

	// CPU port
	input  logic [10:1] cpu_a,
	input  logic  [7:0] cpu_din,     // D15-8
	output logic  [7:0] cpu_dout,
	input  logic        cpu_rw,
	input  logic        cpu_uds_n,
	input  logic        cram_n,      // includes /AS
	input  logic        cbank,

	// video
	input  logic  [8:0] idx,
	input  logic        blank,       // HBLANK or VBLANK for the current count
	output logic [15:0] irgb
);

	logic [7:0] ram [0:2047];

	wire [10:0] ca  = {cbank, cpu_a};
	wire        cwe = ~cram_n & ~cpu_rw & ~cpu_uds_n;

	logic [7:0] cq;
	always_ff @(posedge clk) begin
		if (cwe) begin
			ram[ca] <= cpu_din;
			cq      <= cpu_din;
		end else begin
			cq      <= ram[ca];
		end
	end
	assign cpu_dout = cq;

	logic [7:0] vq;
	always_ff @(posedge clk) vq <= ram[{cbank, idx, half}];

	// what the RAM data pins carry for the video latches
	logic       steal_d, cwe_d;
	logic [7:0] cdin_d;
	always_ff @(posedge clk) begin
		steal_d <= CPU_STEAL & ~cram_n;
		cwe_d   <= cwe;
		cdin_d  <= cpu_din;
	end
	wire [7:0] vdata = !steal_d ? vq : (cwe_d ? cdin_d : cq);

	logic [7:0] l5h, l6h, l7h;
	always_ff @(posedge clk) begin
		if (hclk_fall) l5h <= vdata;
		if (ce_7m) begin
			l6h <= l5h;
			l7h <= vdata;
		end
	end

	assign irgb = blank ? 16'h0000 : {l6h, l7h};

endmodule
