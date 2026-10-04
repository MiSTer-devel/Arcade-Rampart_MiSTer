`timescale 1ns/1ps
//============================================================================
//  rampart_snd_coef_rom - the sound filter coefficients.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  GENERATED FILE, do not edit.  Every value comes from the resistor and
//  capacitor values on the audio sheets, bilinear-transformed at the filter
//  rate clk_sys/576 = 99 431.8 Hz.  Q2.30 signed.
//
//  addr = {set[3:0], term[2:0]}; term 0..4 = b0, b1, b2, -a1, -a2.
//  Sets:
//     0  Y1 MO/RO output RC
//     1  Y2 YMIX 1
//     2  Y2 YMIX 2
//     3  Y2 YMIX 3
//     4  Y2 YMIX 4
//     5  Y2 YMIX 5
//     6  Y2 YMIX 6
//     7  Y2 YMIX 7
//     8  Y3 YM low-pass
//     9  O1 PMIX0 0
//    10  O1 PMIX0 1
//    11  O2 OKI feedback pole
//    12  O3 ladder real pole
//    13  O3 ladder pole pair
//    14  mix weights YM, OKI
//    15  MF mixer pole
//============================================================================

module rampart_snd_coef_rom (
	input  logic [6:0]         addr,
	output logic signed [31:0] c
);
	always_comb begin
		case (addr)
			7'h00: c =  32'sd564133039;
			7'h01: c =  32'sd564133039;
			7'h03: c = -32'sd54524254;
			7'h08: c =  32'sd153340284;
			7'h09: c = -32'sd153340284;
			7'h0B: c =  32'sd1073022147;
			7'h10: c =  32'sd306577825;
			7'h11: c = -32'sd306577825;
			7'h13: c =  32'sd1072302952;
			7'h18: c =  32'sd459712728;
			7'h19: c = -32'sd459712728;
			7'h1B: c =  32'sd1071584238;
			7'h20: c =  32'sd612745094;
			7'h21: c = -32'sd612745094;
			7'h23: c =  32'sd1070866005;
			7'h28: c =  32'sd765675027;
			7'h29: c = -32'sd765675027;
			7'h2B: c =  32'sd1070148252;
			7'h30: c =  32'sd918502630;
			7'h31: c = -32'sd918502630;
			7'h33: c =  32'sd1069430979;
			7'h38: c =  32'sd1071228004;
			7'h39: c = -32'sd1071228004;
			7'h3B: c =  32'sd1068714184;
			7'h40: c =  32'sd324744345;
			7'h41: c =  32'sd324744345;
			7'h43: c =  32'sd424253134;
			7'h48: c =  32'sd357853958;
			7'h49: c = -32'sd357853958;
			7'h4B: c =  32'sd1073381925;
			7'h50: c =  32'sd1073202157;
			7'h51: c = -32'sd1073202157;
			7'h53: c =  32'sd1072662489;
			7'h58: c =  32'sd26340221;
			7'h59: c =  32'sd26340221;
			7'h5B: c =  32'sd1021061382;
			7'h60: c =  32'sd45357305;
			7'h61: c =  32'sd45357305;
			7'h63: c =  32'sd983027214;
			7'h68: c =  32'sd6103754;
			7'h69: c =  32'sd12207508;
			7'h6A: c =  32'sd6103754;
			7'h6B: c =  32'sd2030726850;
			7'h6C: c = -32'sd981400043;
			7'h70: c =  32'sd954437177;
			7'h71: c =  32'sd644245094;
			7'h78: c =  32'sd276521824;
			7'h79: c =  32'sd276521824;
			7'h7B: c =  32'sd520698176;
			default: c = 32'sd0;
		endcase
	end
endmodule
