`timescale 1ns/1ps
//============================================================================
//  Rampart video: raster, bitmap playfield, motion objects, priority,
//  colour RAM and DAC.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  Everything runs on clk_sys (57.27 MHz) with the 14 MHz and 7 MHz
//  enables.  One H count = one 7 MHz pixel = 8 clk_sys.
//
//  Where things land, in H counts h (0..455) of line v (0..261):
//
//      HBLANK (7K pin 12) is low for h = 13..348: column c = h - 13
//      playfield pixel p reaches the DAC in count p + 9, so column c shows
//      VRAM pixel c + 4 of line v
//      the line buffer is read from address 0 in count 11; a motion object
//      at X reaches the DAC in count X + 13, so column c shows LB address c
//      the banks swap and the MOB starts at the end of count 454 (PNXL);
//      it renders line v + 1 + MOB_LINE_ADJ, the line displayed after the
//      next swap
//
//  Parameters (board or best-guess values are the defaults):
//      WAIT_MODEL      0 = the CPU never waits for bitmap or MO RAM;
//                      1 = the 8J / 4L slot timing
//      LB_FIRST_WINS   0 = the last object written wins where two overlap
//      CRAM_CPU_STEAL  1 = a CPU colour-RAM access shows on the pixel;
//                      0 = the pixel always shows its own colour
//      MOB_LINE_ADJ    1 (see above)
//      VS_START/VS_END V sync lines
//
//  The RGB, syncs and blanks leave through one register stage loaded one
//  clk_sys after the pixel edge, so they change together; ce_pix marks the
//  pixel edge.
//============================================================================

module rampart_video #(
	parameter int WAIT_MODEL     = 0,
	parameter bit LB_FIRST_WINS  = 1'b0,
	parameter bit CRAM_CPU_STEAL = 1'b1,
	parameter int MOB_LINE_ADJ   = 1,
	parameter int VS_START       = 243,
	parameter int VS_END         = 247
)(
	input  logic        clk_sys,
	input  logic        ce_14m,
	input  logic        ce_7m,
	input  logic        reset,         // MOB / line buffer only; the raster free-runs

	// CPU bus (selects from the address decoder)
	input  logic [16:1] cpu_a,
	input  logic [15:0] cpu_din,       // CPU write data
	input  logic        cpu_rw,
	input  logic        cpu_as_n,
	input  logic        cpu_uds_n,
	input  logic        cpu_lds_n,
	input  logic        bmsel_n,       // bitmap 0x200000, includes /AS
	input  logic        mosel_n,       // MO RAM 0x3E0000, without /AS
	input  logic        cram_n,        // colour RAM 0x3C0000, includes /AS
	output logic [15:0] bm_dout,
	output logic [15:0] mo_dout,
	output logic  [7:0] cram_dout,     // for D15-8
	output logic        bm_wait,       // 1 = hold DTACK
	output logic        mo_wait,
	input  logic        cbank,         // latch bit 12

	// raster for the CPU side
	output logic  [8:0] hpos,
	output logic  [8:0] vpos,
	output logic        vblank,        // IN0 bit 11, watchdog clock
	output logic        v32,           // 32V, IRQ4 source

	// MO graphics ROM download (raw bytes)
	input  logic        mo_wr,
	input  logic [16:0] mo_addr,
	input  logic  [7:0] mo_data,

	// video out
	input  logic        dac_mame,      // 0 = board DAC levels, 1 = linear
	output logic        ce_pix,
	output logic  [7:0] red,
	output logic  [7:0] green,
	output logic  [7:0] blue,
	output logic        hsync,         // positive
	output logic        vsync,         // positive
	output logic        hblank,
	output logic        vblank_out,
	output logic        csync_n,

	// test taps, aligned with red/green/blue
	output logic  [8:0] dbg_idx,       // colour index of the pixel
	output logic [15:0] dbg_irgb,      // colour word after /BLANK
	output logic        dbg_late       // the MOB missed a line
);

	// ---- raster -------------------------------------------------------------
	logic       hclk_fall, half;
	logic [8:0] h, v;
	logic       vsync_n;

	rampart_sos2 #(.VS_START(VS_START), .VS_END(VS_END)) u_sos2 (
		.clk(clk_sys), .ce_14m(ce_14m), .ce_7m(ce_7m),
		.hclk_fall(hclk_fall), .half(half), .h(h), .v(v),
		.vblank(vblank), .vsync_n(vsync_n), .v32(v32));

	assign hpos = h;
	assign vpos = v;

	logic [20:1] k_i, k_o;
	always_comb begin
		k_i     = '0;
		k_i[9:2] = h[7:0];      // 1H..128H
		k_i[19]  = h[8];        // 256H
	end
	rampart_gal7k u_7k (.clk(clk_sys), .ce(ce_7m), .pin_i(k_i), .pin_o(k_o));

	wire hblank_k  = k_o[12];
	wire hsync_n_k = k_o[13];
	wire nxl_k     = k_o[14];
	wire fetch_off = k_o[15];
	wire lbclr_n   = k_o[16];
	wire pnxl_k    = k_o[17];

	logic hs, vs, cs_n;
	rampart_sync_out u_sync (.clk(clk_sys), .hsync_n(hsync_n_k), .vsync_n(vsync_n),
		.hsync(hs), .vsync(vs), .csync_n(cs_n));

	// ---- bitmap playfield -----------------------------------------------------
	logic [7:0] pf_pix;
	rampart_bitmap #(.WAIT_MODEL(WAIT_MODEL)) u_bm (
		.clk(clk_sys), .ce_14m(ce_14m), .ce_7m(ce_7m), .half(half), .h(h), .v(v),
		.fetch_off(fetch_off),
		.cpu_a(cpu_a), .cpu_din(cpu_din), .cpu_dout(bm_dout), .cpu_rw(cpu_rw),
		.cpu_uds_n(cpu_uds_n), .cpu_lds_n(cpu_lds_n), .bmsel_n(bmsel_n), .cpu_wait(bm_wait),
		.pf_pix(pf_pix));

	// ---- motion objects -------------------------------------------------------
	logic  [1:0] vas;
	logic  [9:4] link_hi;
	logic  [6:1] va_lo;
	logic [15:0] mo_q;

	rampart_moram #(.WAIT_MODEL(WAIT_MODEL)) u_moram (
		.clk(clk_sys), .ce_14m(ce_14m), .half(half), .pnxl(pnxl_k), .nxl(nxl_k),
		.vsync_n(vsync_n),
		.cpu_a(cpu_a[13:1]), .cpu_din(cpu_din), .cpu_dout(mo_dout), .cpu_rw(cpu_rw),
		.cpu_as_n(cpu_as_n), .cpu_uds_n(cpu_uds_n), .cpu_lds_n(cpu_lds_n),
		.mosel_n(mosel_n), .cpu_wait(mo_wait),
		.vas(vas), .link_hi(link_hi), .va_lo(va_lo), .mob_q(mo_q));

	// graphics ROM 2N, 128K x 8, loaded as dumped
	logic [7:0]  rom [0:131071];
	logic [16:0] rom_a;
	logic [7:0]  rom_q;
	always_ff @(posedge clk_sys) begin
		if (mo_wr) rom[mo_addr] <= mo_data;
		rom_q <= rom[rom_a];
	end

	// line strobe: PNXL ends count 454
	wire       swap = ce_7m & pnxl_k;
	wire [9:0] tl   = {1'b0, v} + 10'(1 + MOB_LINE_ADJ);
	wire [8:0] tline = (tl >= 10'd262) ? 9'(tl - 10'd262) : tl[8:0];

	logic       lb_we;
	logic [8:0] lb_wa;
	logic [7:0] lb_wd;
	logic       late, mob_busy;

	rampart_mob u_mob (
		.clk(clk_sys), .reset(reset), .ce_14m(ce_14m),
		.start(swap), .line(tline),
		.vas(vas), .link_hi(link_hi), .va_lo(va_lo), .ram_q(mo_q),
		.rom_a(rom_a), .rom_q(rom_q),
		.lb_we(lb_we), .lb_wa(lb_wa), .lb_wd(lb_wd),
		.busy(mob_busy), .late(late));

	/* verilator lint_off PROCASSINIT */
	logic       wbank = 1'b0;
	logic       rd_en = 1'b0;
	logic       ce_ph0 = 1'b0;
	/* verilator lint_on PROCASSINIT */
	logic [8:0] rd;
	logic [7:0] lb_q, lb_pix;

	always_ff @(posedge clk_sys) begin
		ce_ph0 <= ce_7m;
		if (ce_7m) begin
			lb_pix <= rd_en ? lb_q : 8'd0;
			if (!lbclr_n) begin
				rd    <= 9'd0;
				rd_en <= 1'b1;
			end else begin
				rd <= rd + 9'd1;
			end
			if (pnxl_k) begin
				wbank <= ~wbank;
				rd_en <= 1'b0;
			end
		end
	end

	rampart_lb #(.FIRST_WINS(LB_FIRST_WINS)) u_lb (
		.clk(clk_sys), .reset(reset), .wbank(wbank),
		.we(lb_we), .wa(lb_wa), .wd(lb_wd),
		.rd_ce(ce_ph0 & rd_en), .ra(rd), .q(lb_q));

	// ---- priority, colour RAM, DAC --------------------------------------------
	logic [8:0] idx;
	rampart_mix u_mix (.pf_pix(pf_pix), .mo_pix(lb_pix), .idx(idx));

	logic [15:0] irgb;
	rampart_cram #(.CPU_STEAL(CRAM_CPU_STEAL)) u_cram (
		.clk(clk_sys), .ce_7m(ce_7m), .hclk_fall(hclk_fall), .half(half),
		.cpu_a(cpu_a[10:1]), .cpu_din(cpu_din[15:8]), .cpu_dout(cram_dout),
		.cpu_rw(cpu_rw), .cpu_uds_n(cpu_uds_n), .cram_n(cram_n), .cbank(cbank),
		.idx(idx), .blank(hblank_k | vblank), .irgb(irgb));

	logic [7:0] r8, g8, b8;
	rampart_dac u_dac (.irgb(irgb), .mame(dac_mame), .red(r8), .green(g8), .blue(b8));

	// ---- output stage -----------------------------------------------------------
	logic [8:0] idx_q;
	always_ff @(posedge clk_sys) begin
		if (ce_7m) idx_q <= idx;
		if (ce_ph0) begin
			red        <= r8;
			green      <= g8;
			blue       <= b8;
			hsync      <= hs;
			vsync      <= vs;
			hblank     <= hblank_k;
			vblank_out <= vblank;
			csync_n    <= cs_n;
			dbg_idx    <= idx_q;
			dbg_irgb   <= irgb;
		end
		dbg_late <= late;
	end
	assign ce_pix = ce_7m;

	/* verilator lint_off UNUSEDSIGNAL */
	wire unused_k = &{1'b0, k_o[20:18], k_o[11:1], mob_busy};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
