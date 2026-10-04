`timescale 1ns/1ps
//============================================================================
//  Switch inputs IN0/IN1: the 74LS257 pair at 10B/11B, read at 0x640000.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  /SWITCH = W/R OR /PARALEL; SEL = /A1, so 0x640000 reads IN0 and 0x640002
//  reads IN1.  Only D0-D3 and D8-D11 are driven.  Switches pull their line to
//  ground, so every input here is the board line level (0 = pressed), except
//  VBLANK, which is active high.
//      bit   IN0 (A1 = 0)          IN1 (A1 = 1)
//      D11   VBLANK                SELF-TEST switch
//      D10   P3 button 1 (FIRER)   P3 button 2 (ROTR)
//      D9    P2 button 2 (ROTC)    P1 button 2 (ROTL)
//      D8    P2 button 1 (FIREC)   P1 button 1 (FIREL)
//      D3    strap                 strap
//      D2    strap (players)       COIN L (coin 1)
//      D1    P3 button 2 (ROTR)    COIN R (coin 2)
//      D0    P3 button 1 (FIRER)   SERVICE
//  The P3 buttons reach two bits each through separate resistors.
//  Undriven bits (D4-D7, D12-D15) read OPEN_VALUE.
//============================================================================

module rampart_inputs #(
	parameter bit OPEN_VALUE = 1'b1
) (
	input  logic        a1,
	input  logic        vblank,
	input  logic        firer_n,     // P3 button 1
	input  logic        rotr_n,      // P3 button 2
	input  logic        firec_n,     // P2 button 1
	input  logic        rotc_n,      // P2 button 2
	input  logic        firel_n,     // P1 button 1
	input  logic        rotl_n,      // P1 button 2
	input  logic        coinl_n,
	input  logic        coinr_n,
	input  logic        service_n,
	input  logic        selftest_n,
	input  logic  [2:0] strap,       // {IN1 D3, IN0 D3, IN0 D2}
	output logic [15:0] dout
);

	localparam logic [3:0] OPEN4 = {4{OPEN_VALUE}};

	wire [15:0] in0 = {OPEN4, vblank, firer_n, rotc_n, firec_n,
	                   OPEN4, strap[1], strap[0], rotr_n, firer_n};
	wire [15:0] in1 = {OPEN4, selftest_n, rotr_n, rotl_n, firel_n,
	                   OPEN4, strap[2], coinl_n, coinr_n, service_n};

	assign dout = a1 ? in1 : in0;

endmodule
