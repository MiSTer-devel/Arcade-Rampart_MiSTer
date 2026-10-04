`timescale 1ns/1ps
//============================================================================
//  rampart_ym - the YM2413 at 7C/D: IKAOPLL (Raki, BSD-2-Clause, a model of
//  the chip taken from its die) with the bus write and the audio output
//  adapted to this core.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  ce is XIN (3.579545 MHz, one clk pulse per XIN rising edge).
//
//  Write.  wr is a one-clk strobe with a0/din stable from then on until the
//  next strobe.  IKAOPLL samples /CS and /WR on XIN edges, so the strobe is
//  held until the next ce and the chip sees exactly one write.
//
//  Reset.  rst drives /IC.  While it is held the output is 0.
//
//  Output.  The chip has two impulse DAC pins, MO (melody) and RO (rhythm),
//  and puts one 9-bit sign/magnitude value per slot on them: 18 slots of
//  4 XIN clocks per 72-clock sample (49.7 kHz).  Positive codes read
//  +(mag+1), negative -(mag+1); an idle pin sits at +1 or -1 (the sign of
//  the slot).  The board sums MO and RO with equal weights, so each slot
//  contributes MO + RO, taken once per slot on the 3rd XIN clock of the slot
//  (the DAC is enabled on clocks 2-4).  The slot phase is found from the MO
//  enable, which rises on the 2nd clock of every melody slot.
//  out is the sum of the last 18 slots (one sample period) times 16, updated
//  every slot and saturated to 16 bits.  x16 puts one DAC step at 16 LSB,
//  the scale the rest of the audio path is calibrated for (a 13-bit
//  operator output per channel).  The rhythm voices appear in as many RO
//  slots as the chip gives them.
//============================================================================

module rampart_ym (
	input  logic              clk,
	input  logic              rst,
	input  logic              ce,
	input  logic              wr,
	input  logic              a0,
	input  logic        [7:0] din,
	output logic signed [15:0] out,
	output logic              out_stb     // one clk when out updates
);

	// ---- the write, held until the chip has sampled it on an XIN edge ----
	logic wr_pend;
	always_ff @(posedge clk) begin
		if (rst)      wr_pend <= 1'b0;
		else if (wr)  wr_pend <= 1'b1;
		else if (ce)  wr_pend <= 1'b0;
	end

	// ---- the chip ----
	wire               dac_en_mo;
	wire signed [9:0]  pin_mo, pin_ro;
	// unused chip outputs
	wire               nc_xout, nc_d_oe, nc_en_ro, nc_sign, nc_acc_stb;
	wire        [1:0]  nc_d;
	wire        [7:0]  nc_mag;
	wire signed [15:0] nc_acc;

	IKAOPLL #(
		.FULLY_SYNCHRONOUS        (1),
		.FAST_RESET               (0),
		.ALTPATCH_CONFIG_MODE     (0),
		.USE_PIPELINED_MULTIPLIER (1)
	) u_opll (
		.i_XIN_EMUCLK         (clk),
		.o_XOUT               (nc_xout),
		.i_phiM_PCEN_n        (~ce),
		.i_IC_n               (~rst),
		.i_ALTPATCH_EN        (1'b0),
		.i_CS_n               (~wr_pend),
		.i_WR_n               (~wr_pend),
		.i_A0                 (a0),
		.i_D                  (din),
		.o_D                  (nc_d),
		.o_D_OE               (nc_d_oe),
		.o_DAC_EN_MO          (dac_en_mo),
		.o_DAC_EN_RO          (nc_en_ro),
		.o_IMP_NOFLUC_SIGN    (nc_sign),
		.o_IMP_NOFLUC_MAG     (nc_mag),
		.o_IMP_FLUC_SIGNED_MO (pin_mo),
		.o_IMP_FLUC_SIGNED_RO (pin_ro),
		.i_ACC_SIGNED_MOVOL   (5'sd1),
		.i_ACC_SIGNED_ROVOL   (5'sd1),
		.o_ACC_SIGNED_STRB    (nc_acc_stb),
		.o_ACC_SIGNED         (nc_acc)
	);

	wire _unused = &{1'b0, nc_xout, nc_d, nc_d_oe, nc_en_ro, nc_sign, nc_mag,
	                 nc_acc_stb, nc_acc};

	// ---- slot phase: 0..3 = the XIN clock within the slot ----
	logic [1:0] ph;
	logic       en_mo_d, locked;
	always_ff @(posedge clk) begin
		if (rst) begin
			ph      <= 2'd0;
			en_mo_d <= 1'b0;
			locked  <= 1'b0;
		end else if (ce) begin
			en_mo_d <= dac_en_mo;
			if (dac_en_mo && !en_mo_d) begin
				ph     <= 2'd2;           // this clock is the 2nd of the slot
				locked <= 1'b1;
			end else begin
				ph <= ph + 2'd1;
			end
		end
	end
	wire take = ce && locked && (ph == 2'd2);

	// ---- the last 18 slots and their sum ----
	wire signed [10:0] slot_val = 11'(pin_mo) + 11'(pin_ro);
	logic signed [10:0] hist [0:17];
	logic signed [14:0] sum;
	wire  signed [14:0] sum_nx = sum + 15'(slot_val) - 15'(hist[17]);
	wire  signed [18:0] scaled = 19'(sum_nx) <<< 4;

	always_ff @(posedge clk) begin
		out_stb <= 1'b0;
		if (rst) begin
			for (int i = 0; i < 18; i++) hist[i] <= 11'sd0;
			sum <= 15'sd0;
			out <= 16'sd0;
		end else if (take) begin
			hist[0] <= slot_val;
			for (int i = 1; i < 18; i++) hist[i] <= hist[i-1];
			sum     <= sum_nx;
			out_stb <= 1'b1;
			if (scaled > 19'sd32767)       out <= 16'sd32767;
			else if (scaled < -19'sd32768) out <= -16'sd32768;
			else                           out <= scaled[15:0];
		end
	end

endmodule
