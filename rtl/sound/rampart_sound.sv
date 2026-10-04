`timescale 1ns/1ps
//============================================================================
//  rampart_sound - the Rampart sound system: YM2413 at 7C/D (rampart_ym),
//  MSM6295 at 5D, the 5L/5K clock divider, and the analogue level switches,
//  filters and mixer as one digital filter chain.  There is no sound CPU:
//  the 68000 writes both chips directly.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  Clocks.  ce_3m58 is 1H, the YM2413 XIN (one clk_sys pulse per 1H rising
//  edge, clk_sys/16).  The OKI XT is 1H / 3 from an XOR (5L) and two toggle
//  flip-flops (5K) with no preset or clear: XT rises on every third rising
//  edge of 1H, and which one of the three is fixed at power-on.  Here that
//  phase is fixed at FPGA configuration.  The filter chain ticks every 36th
//  1H edge (clk_sys/576 = 99 431.8 Hz), which is also the audio rate.
//
//  Bus.  ym_cs is the /YAMAHA select (high = selected) for the length of a
//  CPU write; A0 is CPU A1 and the data is CPU D15..D8.  The chip latches on
//  the rising edge of /CS, so the write is committed when ym_cs falls, with
//  the address and data seen on the last selected clock.  oki_wr is the OKI
//  /WR strobe (high = low on the pin) with the command on D15..D8, committed
//  the same way.  oki_dout is the status byte ($F0 | playing voices) that
//  the chip drives onto D15..D8 when read; a read has no side effect.
//
//  Resets.  yamres_n and pcmres_n are latch bits 0 and 4, levels: a chip is
//  held in reset, ignoring writes and silent, for as long as its bit is 0.
//  The board's /RESET clears the latch, so at power-on both chips are held.
//  reset (active high) clears this block's own state (filters, strobes).
//
//  ADPCM ROM port (18-bit OKI address, 256 KB: 1007 then 1008).  oki_rom_req
//  rises with a stable oki_rom_addr and both are held until the one-clk
//  oki_rom_ack, which carries the byte on oki_rom_data.  One request is
//  outstanding at a time.  Commands act between the same two samples at any
//  latency, as long as the six table reads that start a phrase (about
//  6 x (latency + 3) clocks) finish before the CPU's next OKI write.  The
//  game writes at most every 496 clocks, so a latency of up to 70 clocks is
//  exact, and every sample stays on time up to about 700 clocks.
//
//  Output: audio, signed 16-bit mono, updated with a one-clk audio_stb at
//  99 431.8 Hz.  It is the mixer output (before the volume pot and the power
//  amplifier); full scale matches MAME's mix at the game's settings.
//============================================================================

module rampart_sound (
	input  logic        clk_sys,
	input  logic        reset,
	input  logic        ce_3m58,          // 1H

	// ---- YM2413 (0x480000 address, 0x480002 data, D15..D8) ----
	input  logic        ym_cs,
	input  logic        ym_a0,
	input  logic  [7:0] ym_din,

	// ---- MSM6295 (0x460000, D15..D8) ----
	input  logic        oki_wr,
	input  logic  [7:0] oki_din,
	output logic  [7:0] oki_dout,

	// ---- sound latch 6C bits (0x640000 low byte) ----
	input  logic        yamres_n,         // bit 0
	input  logic  [2:0] ymix,             // bits 3..1
	input  logic        pcmres_n,         // bit 4
	input  logic        pmix0,            // bit 5

	// ---- ADPCM ROM, toward the SDRAM arbiter ----
	output logic        oki_rom_req,
	output logic [17:0] oki_rom_addr,
	input  logic        oki_rom_ack,
	input  logic  [7:0] oki_rom_data,

	// ---- audio ----
	output logic signed [15:0] audio,
	output logic        audio_stb
);

	// ================= clock enables =========================================
	// 5L/5K: XT follows every third 1H rising edge.  No reset, as on the board.
	/* verilator lint_off PROCASSINIT */
	logic [1:0] xt_phase = 2'd0;
	/* verilator lint_on PROCASSINIT */
	always_ff @(posedge clk_sys)
		if (ce_3m58) xt_phase <= (xt_phase == 2'd2) ? 2'd0 : xt_phase + 2'd1;
	wire ce_1m19 = ce_3m58 && (xt_phase == 2'd2);

	logic [5:0] tick_cnt;
	logic       tick;
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			tick_cnt <= 6'd0;
			tick     <= 1'b0;
		end else begin
			tick <= 1'b0;
			if (ce_3m58) begin
				if (tick_cnt == 6'd35) begin
					tick_cnt <= 6'd0;
					tick     <= 1'b1;
				end else begin
					tick_cnt <= tick_cnt + 6'd1;
				end
			end
		end
	end

	// ================= the write strobes (committed on the trailing edge) ====
	logic       ym_cs_d, ym_a0_l, ym_wr;
	logic [7:0] ym_din_l;
	logic       oki_wr_d, oki_wr_p;
	logic [7:0] oki_din_l;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			ym_cs_d   <= 1'b0;
			ym_a0_l   <= 1'b0;
			ym_din_l  <= 8'd0;
			ym_wr     <= 1'b0;
			oki_wr_d  <= 1'b0;
			oki_din_l <= 8'd0;
			oki_wr_p  <= 1'b0;
		end else begin
			ym_cs_d  <= ym_cs;
			oki_wr_d <= oki_wr;
			if (ym_cs) begin
				ym_a0_l  <= ym_a0;
				ym_din_l <= ym_din;
			end
			if (oki_wr) oki_din_l <= oki_din;
			ym_wr    <= ym_cs_d & ~ym_cs;
			oki_wr_p <= oki_wr_d & ~oki_wr;
		end
	end

	// ================= YM2413 ===============================================
	wire ym_rst = reset | ~yamres_n;
	wire signed [15:0] ym_out;
	wire ym_stb;

	rampart_ym u_ym (
		.clk     (clk_sys),
		.rst     (ym_rst),
		.ce      (ce_3m58),
		.wr      (ym_wr),
		.a0      (ym_a0_l),
		.din     (ym_din_l),
		.out     (ym_out),
		.out_stb (ym_stb)
	);

	// ================= MSM6295 ===============================================
	wire signed [15:0] oki_audio;

	rampart_oki u_oki (
		.clk      (clk_sys),
		.ce_1m19  (ce_1m19),
		.okires_n (pcmres_n & ~reset),
		.wr_stb   (oki_wr_p),
		.wr_data  (oki_din_l),
		.rd_data  (oki_dout),
		.oki_req  (oki_rom_req),
		.oki_addr (oki_rom_addr),
		.oki_ack  (oki_rom_ack),
		.oki_data (oki_rom_data),
		.audio    (oki_audio)
	);

	// ================= level switches, filters, mixer ========================
	wire signed [31:0] m1_full;

	rampart_snd_filter u_filter (
		.clk       (clk_sys),
		.reset     (reset),
		.tick      (tick),
		.ym_in     (ym_out),
		.oki_in    (oki_audio),
		.ymix      (ymix),
		.pmix0     (pmix0),
		.audio     (audio),
		.audio_stb (audio_stb),
		.m1_full   (m1_full)
	);

	wire _unused = &{1'b0, ym_stb, m1_full};

endmodule
