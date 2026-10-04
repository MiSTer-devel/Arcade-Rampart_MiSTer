`timescale 1ns/1ps
//============================================================================
//  rampart_snd_filter - the analogue audio path of the board (the op-amp
//  filters, level switches and mixer on the two audio sheets) as fixed-point
//  IIR sections.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  The one-section-per-RC-stage structure follows the sound filters of the
//  Skull & Crossbones and Batman MiSTer cores (GPL-3.0); the sections here
//  are bilinear-transformed biquads computed one after another on a single
//  multiplier.
//
//  Sections, in processing order (all run once per tick):
//    0 Y1  YM MO/RO output RC (4.7K, 1 nF): low-pass 33.9 kHz
//    1 Y2  YM level switch into the 1 uF coupling cap: high-pass
//          10.6 Hz x YMIX, gain YMIX/7; YMIX = 0 (all switches open) gives
//          silence and freezes this section's state
//    2 Y3  YM low-pass 12K/1 nF as drawn: 13.3 kHz
//    3 O1  OKI input network: high-pass 15.9 Hz gain 1 (PMIX0 = 1) or
//          5.3 Hz gain 1/3 (PMIX0 = 0)
//    4 O2  OKI feedback pole 20K || 10 nF: 795.8 Hz
//    5 O3a OKI third-order ladder, real pole 1395 Hz
//    6 O3b OKI third-order ladder, pole pair 2442 Hz, Q 1.71
//    7 MIX the summing amplifier: w_ym * Y3 + w_oki * O3b
//    8 MF  mixer feedback pole 15K || 1 nF: 10.6 kHz
//  The YM2413's melody and rhythm outputs have identical networks and equal
//  resistor weights, so the chip's summed output goes through one YM path.
//  The YM:OKI balance at the game's setting (YMIX 7, PMIX0 1) is MAME's,
//  because the two chips' DAC voltages are not on the schematic.
//
//  Arithmetic: signals are 32-bit signed with 12 fraction bits below the
//  16-bit input LSB; coefficients Q2.30 from rampart_snd_coef_rom;
//      y = sat32((b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2 + 2^29) >>> 30)
//  (direct form I, one 32 x 32 multiply per clk_sys step, 16 clocks per
//  section, 144 per tick).  audio = sat16((MF + 2^11) >>> 12).
//
//  tick: one clk pulse per output sample, at least 160 clocks apart.  In the
//  core it is clk_sys/576 = 99 431.8 Hz.  Inputs are sampled on the tick.
//============================================================================

module rampart_snd_filter (
	input  logic               clk,
	input  logic               reset,
	input  logic               tick,
	input  logic signed [15:0] ym_in,       // YM2413 MO + RO (rampart_ym)
	input  logic signed [15:0] oki_in,      // MSM6295 DA0
	input  logic         [2:0] ymix,        // latch YMIX2..0
	input  logic               pmix0,       // latch PMIX0
	output logic signed [15:0] audio,
	output logic               audio_stb,   // one clk when audio updates
	output logic signed [31:0] m1_full      // the MF output at full precision
);

	localparam int FRAC = 12;
	localparam int QC   = 30;

	localparam logic [3:0] SEC_Y1 = 4'd0, SEC_Y2 = 4'd1, SEC_Y3 = 4'd2,
	                       SEC_O1 = 4'd3, SEC_O3B = 4'd6, SEC_MIX = 4'd7,
	                       SEC_M1 = 4'd8;

	// ---- section state (direct form I) ----
	logic signed [31:0] x1 [0:8];
	logic signed [31:0] x2 [0:8];
	logic signed [31:0] y1 [0:8];
	logic signed [31:0] y2 [0:8];

	// ---- inputs, sampled on the tick ----
	logic signed [31:0] xin_ym, xin_oki;
	logic         [2:0] ymix_r;
	logic               pmix_r;

	// ---- the sequencer ----
	logic               busy;
	logic         [3:0] sec;
	logic         [2:0] term;
	logic         [1:0] phase;
	logic signed [31:0] cur;           // output of the previous section
	logic signed [31:0] coef_r, op_r;
	logic signed [63:0] prod_r;
	logic signed [65:0] acc;

	// coefficient set of each section
	logic [3:0] cset;
	always_comb begin
		case (sec)
			4'd0:    cset = 4'd0;
			4'd1:    cset = {1'b0, ymix_r};
			4'd2:    cset = 4'd8;
			4'd3:    cset = pmix_r ? 4'd10 : 4'd9;
			4'd4:    cset = 4'd11;
			4'd5:    cset = 4'd12;
			4'd6:    cset = 4'd13;
			4'd7:    cset = 4'd14;
			default: cset = 4'd15;
		endcase
	end

	logic signed [31:0] rom_c;
	rampart_snd_coef_rom u_rom (.addr({cset, term}), .c(rom_c));

	// the section's input sample
	wire signed [31:0] xcur = (sec == SEC_Y1) ? xin_ym
	                        : (sec == SEC_O1) ? xin_oki
	                        : cur;

	logic signed [31:0] operand;
	always_comb begin
		case (term)
			3'd0:    operand = (sec == SEC_MIX) ? y1[SEC_Y3]  : xcur;
			3'd1:    operand = (sec == SEC_MIX) ? y1[SEC_O3B] : x1[sec];
			3'd2:    operand = x2[sec];
			3'd3:    operand = y1[sec];
			default: operand = y2[sec];
		endcase
	end

	// rounding and saturation
	wire signed [65:0] acc_rnd = acc + (66'sd1 <<< (QC - 1));
	wire signed [35:0] acc_sh  = 36'(acc_rnd >>> QC);    // |acc| < 2^65
	wire signed [31:0] y_new   = (acc_sh >  36'sh07FFFFFFF) ? 32'sh7FFFFFFF
	                           : (acc_sh < -36'sh080000000) ? 32'sh80000000
	                           : acc_sh[31:0];
	wire signed [32:0] out_rnd = 33'(y_new) + (33'sd1 <<< (FRAC - 1));
	wire signed [20:0] out_sh  = 21'(out_rnd >>> FRAC);
	wire signed [15:0] out16   = (out_sh >  21'sh007FFF) ? 16'sh7FFF
	                           : (out_sh < -21'sh008000) ? 16'sh8000
	                           : out_sh[15:0];

	always_ff @(posedge clk) begin
		if (reset) begin
			busy      <= 1'b0;
			sec       <= 4'd0;
			term      <= 3'd0;
			phase     <= 2'd0;
			cur       <= 32'sd0;
			coef_r    <= 32'sd0;
			op_r      <= 32'sd0;
			prod_r    <= 64'sd0;
			acc       <= 66'sd0;
			xin_ym    <= 32'sd0;
			xin_oki   <= 32'sd0;
			ymix_r    <= 3'd0;
			pmix_r    <= 1'b0;
			audio     <= 16'sd0;
			audio_stb <= 1'b0;
			m1_full   <= 32'sd0;
			for (int k = 0; k < 9; k++) begin
				x1[k] <= 32'sd0; x2[k] <= 32'sd0; y1[k] <= 32'sd0; y2[k] <= 32'sd0;
			end
		end else begin
			audio_stb <= 1'b0;
			if (!busy) begin
				if (tick) begin
					xin_ym  <= 32'(ym_in)  <<< FRAC;
					xin_oki <= 32'(oki_in) <<< FRAC;
					ymix_r  <= ymix;
					pmix_r  <= pmix0;
					busy    <= 1'b1;
					sec     <= 4'd0;
					term    <= 3'd0;
					phase   <= 2'd0;
					acc     <= 66'sd0;
				end
			end else if (sec == SEC_Y2 && ymix_r == 3'd0) begin
				// all level switches open: no signal, the state is frozen
				cur <= 32'sd0;
				sec <= sec + 4'd1;
			end else begin
				case (phase)
					2'd0: begin
						coef_r <= rom_c;
						op_r   <= operand;
						phase  <= 2'd1;
					end
					2'd1: begin
						prod_r <= coef_r * op_r;
						phase  <= 2'd2;
					end
					2'd2: begin
						acc <= acc + 66'(prod_r);
						if (term == 3'd4) begin
							phase <= 2'd3;
						end else begin
							term  <= term + 3'd1;
							phase <= 2'd0;
						end
					end
					default: begin
						if (sec != SEC_MIX) begin
							x2[sec] <= x1[sec];
							x1[sec] <= xcur;
							y2[sec] <= y1[sec];
						end
						y1[sec] <= y_new;
						cur     <= y_new;
						acc     <= 66'sd0;
						term    <= 3'd0;
						phase   <= 2'd0;
						if (sec == SEC_M1) begin
							audio     <= out16;
							audio_stb <= 1'b1;
							m1_full   <= y_new;
							busy      <= 1'b0;
						end else begin
							sec <= sec + 4'd1;
						end
					end
				endcase
			end
		end
	end

endmodule
