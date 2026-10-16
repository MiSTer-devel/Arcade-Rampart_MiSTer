// Rampart analog-output alignment stage: the OSD decode, the read-rate
// generator and the blanking glue around rmonic79's `crt_adjust`
// (rtl/video/crt_adjust.sv, vendored from MiSTer-CRT-Adjust).  Written from
// that project's examples/core_side_snippet.v (GPL-3.0, Umberto Parisi) by way
// of the Blasteroids MiSTer core (GPL-3.0), re-derived for an 8-clock pixel and
// for feeding arcade_video rather than the VGA_* pins directly.
//
// Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
// The OSD carries three controls plus an On/Off: CRT H-Size, CRT H-Position and
// CRT V-Shift.  H-Position has two possible mechanisms inside `crt_adjust`,
// picked at compile time by `HPOS_MODE`:
//
//   HPOS_CONTENTSHIFT (1)  shifts the CONTENT in the line buffer, HSync native
//   HPOS_SYNCSHIFT    (0)  shifts the HSYNC, content native
//
// Only one of the two is built, and the whole engine restarts on one line
// reference, `hs_ref_out`.  The read-rate accumulator below must be reset on
// that edge rather than on the raw HSync, or the picture trembles.
//
// ---------------- the Rampart raster ----------------------------------------
// One count is one 7 MHz pixel (ce_pix = clk_sys/8):
//
//     line total        456 counts, 262 lines
//     active            counts 13 .. 348          (336 px), lines 0 .. 239
//     HSync high        counts 380 .. 407
//
// The line counter, and so VBlank, advances at the wrap from 455 to 0, and
// HSync comes AFTER the active pixels.  The line-buffer bank that closes at the
// HSync rise of line L therefore already holds line L, which is why the engine
// is built with VB_LATE = 0 (see crt_adjust.sv).
//
// ---------------- HPOS_MODE for Rampart: CONTENTSHIFT -----------------------
// Upstream's rule is "CONTENTSHIFT for wide/centred games, SYNCSHIFT for narrow
// side-anchored ones, because CONTENTSHIFT runs the picture out of the buffer
// window on the short-margin side and shows a black block there".
//
// The line buffer's write pointer resets on the HSync rise, so in BUFFER
// coordinates the active region is 89 .. 424 of 456: an 89-pixel left margin
// and a 31-pixel right one, so the short margin is the RIGHT one.  At H-Size 0
// a line delivers 456 read ticks, so H-Position is lossless up to +31; beyond
// that the right edge runs out of the line and shows black.  Every negative
// setting is safe (89 - 64 still leaves a 25-pixel left margin).
//
// CONTENTSHIFT is still the more useful mode here.  Enlarging (H-Size > 0)
// slows the read, so the left margin is stretched too and the right of the
// picture runs off the end of the line: at H-Position 0 the whole picture
// fits up to H-Size +4 (456 * 64/68 = 429 ticks), and at +15 (369 ticks) it
// needs H-Position -56 or less.  A NEGATIVE H-Position pulls the content
// earlier and buys that room back.  SYNCSHIFT cannot do that -- it moves the
// sync and the content together, so it re-centres the picture on the tube but
// never changes what fits in a line.
//
// If a real CRT ever shows a black block at the right edge where it should
// not, HPOS_MODE = 0 is the one-line fallback and nothing else changes.
//
// ---------------- the read rate, and why 64/CLK_PER_PIX ---------------------
// Upstream steps the read period in quarter clocks because its reference core's
// pixel is 16 clk_sys cycles: 64 quarters = one pixel, so one H-Size click is
// 1/64 = 1.56%.  Ours is 8 (ce_7m), and a fixed quarter-clock step would make
// one click 3.1% instead.  The accumulator below counts 1/CLK_PER_PIX-th of a
// clock instead, which keeps the 1.56% step at any pixel period:
//
//     period = 64 + hsize      units, where 64 units == CLK_PER_PIX clocks
//     acc   += 64/CLK_PER_PIX  per clock
//
// so hsize spans 48..79 units = 6.00..9.88 clocks per pixel at CLK_PER_PIX = 8.
// ACC_STEP must stay an exact integer -- 64/CLK_PER_PIX with CLK_PER_PIX a
// power of two -- or the OSD step silently drifts away from the menu text.
//
// ---------------- where this sits, and the DE it hands on -------------------
// Between rampart_core and arcade_video, so the mixer, the scandoubler, gamma
// and video_freak all see the adjusted raster and the adjusted pixel enable.
// Nothing here touches the core's own timing: the pixel clock and the native
// sync rates are untouched, so there is no jitter and nothing the game can see.
//
// Upstream's core-side glue also builds a `de_osd` window whose rising edge is
// pinned to the NATIVE active region, so the MiSTer OSD (which centres itself on
// the rise of VGA_DE) does not slide when H-Position moves the picture.  This
// core deliberately does not use it -- see the DE section below for why.
//
// All three OSD fields are plain two's complement, so the config string just
// lists 0,+1..+max then -min..-1 and the decode is a $signed().

module rampart_analog_adjust #(
	parameter int H_TOTAL     = 456,   // ce_pix ticks per line
	parameter int V_TOTAL     = 262,   // lines per frame
	parameter int CLK_PER_PIX = 8,     // clk_sys cycles per ce_pix (ce_7m = clk_sys/8)
	parameter int HPOS_MODE   = 1,     // 1 = CONTENTSHIFT, 0 = SYNCSHIFT (see above)
	parameter int AW          = 11     // line-buffer address bits (1024 per bank)
) (
	input  logic       clk,
	input  logic       ce_pix,

	// OSD
	input  logic       osd_on,         // CRT Adjust Off/On; Off is a bit-exact bypass
	input  logic [4:0] osd_hsize,      // CRT H-Size        +15 / -16   two's complement
	input  logic [6:0] osd_hpos,       // CRT H-Position    +63 / -64   two's complement
	input  logic [5:0] osd_vshift,     // CRT V-Shift       +31 / -32   two's complement

	input  logic [7:0] r_in, g_in, b_in,
	input  logic       hs_in, vs_in, hb_in, vb_in,

	output logic [7:0] r_out, g_out, b_out,
	output logic       hs_out, vs_out, hb_out, vb_out,
	output logic       ce_out
);

	localparam [7:0] ACC_STEP = 8'(64 / CLK_PER_PIX);

	// ---------------- OSD decode ----------------
	// Everything is sampled at ce_pix so a mid-frame menu change lands on a
	// pixel boundary rather than anywhere inside one.
	logic              active;
	logic signed [4:0] hsize_s;
	logic signed [8:0] hpos_s;
	logic signed [5:0] vshift_s;

	always_ff @(posedge clk) if (ce_pix) begin
		active   <= osd_on;
		hsize_s  <= $signed(osd_hsize);
		hpos_s   <= 9'($signed(osd_hpos));    // sign-extend 7 -> 9 bits
		vshift_s <= $signed(osd_vshift);
	end

	// ---------------- read-rate generator ----------------
	// The wiring rule: reset the accumulator on the rise of the module's
	// `hs_ref_out`, never on the raw HSync, so the write side, the module's read
	// counter and this read rate all restart on the same edge.
	wire  hs_ref;
	logic hs_ref_d;
	always_ff @(posedge clk) hs_ref_d <= hs_ref;
	wire  hs_ref_rise = hs_ref & ~hs_ref_d;

	wire  [7:0] rd_period = 8'd64 + {{3{hsize_s[4]}}, hsize_s};   // 48..79
	logic [7:0] rd_acc;
	wire        rd_tick = (rd_acc + ACC_STEP) >= rd_period;

	always_ff @(posedge clk) begin
		if      (hs_ref_rise) rd_acc <= 8'd0;
		else if (rd_tick)     rd_acc <= rd_acc + ACC_STEP - rd_period;
		else                  rd_acc <= rd_acc + ACC_STEP;
	end

	// When On the line buffer is always live -- even at H-Size 0, where rd_tick
	// runs at the same average rate as ce_pix but re-phased onto hs_ref.
	wire rd_ce = active ? rd_tick : ce_pix;

	// ---------------- the engine ----------------
	wire [7:0] str_r, str_g, str_b;
	wire       str_hs, str_vs, str_hb, str_vb;

	crt_adjust #(
		.VTOTAL    (V_TOTAL),
		.HTOTAL    (H_TOTAL),
		.HPOS_MODE (HPOS_MODE),
		.AW        (AW),
		.VB_LATE   (0)              // HSync follows the active pixels (see above)
	) u_crt_adjust (
		.clk        (clk),
		.pxl_cen    (ce_pix),
		.pxl2_cen   (rd_ce),
		.active     (active),
		.hsize      (hsize_s),      // kept for upstream parity; the rate above is H-Size
		.hoffset    (hpos_s),
		.voffset    (vshift_s),
		.r_in       (r_in), .g_in (g_in), .b_in (b_in),
		.hs_in      (hs_in),        // NATIVE sync in -- the module derives hs_ref itself
		.vs_in      (vs_in),
		.hb_in      (hb_in | vb_in),
		.vb_in      (vb_in),        // TRUE vertical blank, not the combined blank
		.r_out      (str_r), .g_out (str_g), .b_out (str_b),
		.hs_out     (str_hs), .vs_out (str_vs),
		.hb_out     (str_hb), .vb_out (str_vb),
		.hs_ref_out (hs_ref)
	);

	// ---------------- the vertical blank handed to arcade_video ------------
	// arcade_video latches VBlank where HBlank falls, so the vblank it gets must
	// line up with the line the read side is emitting, not with the native
	// write-rate blank.  `str_vb` is the native one: handing it on would blank
	// the last visible line while the read side is still emitting it.  `vb_read`
	// below is a replica of the module's own gate (`vb_active`, built with
	// VB_LATE = 0), sampled on the same `hs_ref` edge, so DE goes low over
	// exactly the lines `pass_q` is already suppressing and no line is lost or
	// repeated.  It must stay ONE flop while the engine is VB_LATE = 0; a second
	// flop shows a stale line under the picture.
	logic hs_ref_q;
	always_ff @(posedge clk) if (ce_pix) hs_ref_q <= hs_ref;
	wire  ref_line_tick = ce_pix & hs_ref & ~hs_ref_q;

	logic vb_read;
	always_ff @(posedge clk) if (ref_line_tick) vb_read <= vb_in;

	// ---------------- what is NOT here: upstream's `de_osd` ----------------
	// Upstream's core-side snippet hands the framework a DE window whose rising
	// edge is anchored to the native active region and whose falling edge
	// follows the stretched one, so the MiSTer OSD -- which centres itself on
	// the rise of VGA_DE -- stays put while H-Position moves the picture.  It
	// does not work on this raster.
	//
	// It assumes the stretched active never STARTS before the native one.  Our
	// active region sits 89 pixels into the line buffer, and pulling the content
	// left is exactly what a negative H-Position is for here -- it is the
	// direction that buys back room when H-Size enlarges.  The moment `hoffset`
	// goes negative the content opens before the window does, everything to the
	// left of the native active start is DE-blanked, and if the content finishes
	// before the native rise the window opens on nothing and stays open across
	// HSync.
	//
	// So DE here simply follows the picture.  The cost is the one upstream set
	// out to remove: the OSD slides with H-Position.  An anchored window would
	// need its rising edge at the EARLIER of the native and the stretched
	// active, and would have to suppress the native rise on a line whose
	// stretched active has already ended.

	// ---------------- outputs ----------------
	// Off: `crt_adjust` is in its own pure bypass, so everything here is the
	// native stream delayed by the module's two input registers.
	assign r_out  = str_r;
	assign g_out  = str_g;
	assign b_out  = str_b;
	assign hs_out = str_hs;
	assign vs_out = str_vs;
	assign hb_out = str_hb;
	assign vb_out = active ? vb_read : str_vb;
	assign ce_out = rd_ce;

endmodule
