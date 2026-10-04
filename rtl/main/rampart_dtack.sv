`timescale 1ns/1ps
//============================================================================
//  /DTACK and /VPA for the main CPU.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  Interrupt acknowledge cycles (FC = 7) get /VPA and never /DTACK: the
//  program uses the level-4 autovector.  Every other cycle completes,
//  including cycles to addresses where nothing is decoded.
//
//  The DTACK generator is not on any published sheet, so the wait states are
//  a parameter:
//    WAIT_MODEL 0: no wait states anywhere (four-clock bus cycles).
//    WAIT_MODEL 1: the model derived from the GAL fuse maps, part speeds
//                  and Atari's sibling boards of the same period: EEPROM
//                  +1, MSM6295, YM2413 and LETA +2 each, MO RAM +1 and
//                  stretched while the MO arbiter holds its ready low,
//                  bitmap RAM held until the DRAM sequencer's CPU slot is
//                  ready.
//  The program ROM is served from SDRAM; its data normally arrives before
//  /DTACK is sampled, and rom_ready only adds a wait if it does not.
//
//  fx68k samples /DTACK on CPU clock falling edges (en_phi2).  /AS asserts
//  on a rising edge; the second falling edge after it is the last one that
//  still gives a four-clock cycle.  So "N wait states" means /DTACK first
//  seen on the (2 + N)th falling edge after /AS.
//============================================================================

module rampart_dtack #(
	parameter int WAIT_MODEL = 0
) (
	input  logic       clk,
	input  logic       en_phi2,
	input  logic       as,
	input  logic [2:0] fc,
	input  logic       rom_sel,
	input  logic       rom_ready,
	input  logic       bmsel_n,
	input  logic       mosel_n,
	input  logic       eeprom_n,
	input  logic       adpcm_n,
	input  logic       yamaha_n,
	input  logic       leta_n,
	input  logic       bm_ready,    // bitmap RAM CPU slot ready
	input  logic       mo_ready,    // MO RAM arbiter ready
	output logic       dtack,
	output logic       vpa_n,
	// 1-clk: /DTACK sampled high only because ROM data was not ready
	output logic       rom_late
);

	wire iack = (fc == 3'b111);
	assign vpa_n = ~(as & iack);

	// falling edges seen since /AS asserted
	logic [3:0] nph2;
	always_ff @(posedge clk) begin
		if (!as)                       nph2 <= 4'd0;
		else if (en_phi2 && nph2 != 4'hF) nph2 <= nph2 + 4'd1;
	end

	wire [3:0] waits = (WAIT_MODEL != 1) ? 4'd0 :
	                   !adpcm_n  ? 4'd2 :
	                   !yamaha_n ? 4'd2 :
	                   !leta_n   ? 4'd2 :
	                   !eeprom_n ? 4'd1 :
	                   !mosel_n  ? 4'd1 : 4'd0;

	wire held = (WAIT_MODEL == 1) && ((!bmsel_n && !bm_ready) || (!mosel_n && !mo_ready));

	wire due = as && !iack && (nph2 >= 4'd1 + waits) && !held;
	assign dtack    = due && (!rom_sel || rom_ready);
	assign rom_late = en_phi2 && due && rom_sel && !rom_ready;

endmodule
