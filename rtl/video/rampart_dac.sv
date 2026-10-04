`timescale 1ns/1ps
//============================================================================
//  Rampart video DAC (RP1-RP3 ladders, LS260 + 7406 black clamp, 2N3904
//  followers).
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  Adapted from batman_dac.sv of the Batman MiSTer core (GPL-3.0).
//
//  Each gun is a 6-bit R-2R ladder, code = {gun[4:0], I}, where I (colour
//  bit 15) is the shared LSB.  The ladder node has a 2.4K pull-up, and a
//  7406 pulls it down through 1K when all five gun bits are zero.  So gun 0
//  is the blanking level and every other gun value sits on a pedestal.
//  The board table below is that circuit normalised to 0 (gun 0) .. 255
//  (code 63).  mame = 1 selects the plain linear scale instead,
//  (code << 2) | (code >> 4), with no clamp.
//============================================================================

module rampart_dac (
	input  logic [15:0] irgb,
	input  logic        mame,
	output logic  [7:0] red,
	output logic  [7:0] green,
	output logic  [7:0] blue
);

	function automatic logic [7:0] board(input logic [5:0] c);
		case (c)
			6'd0:  board = 8'd0;   6'd1:  board = 8'd2;   6'd2:  board = 8'd41;  6'd3:  board = 8'd45;
			6'd4:  board = 8'd48;  6'd5:  board = 8'd51;  6'd6:  board = 8'd55;  6'd7:  board = 8'd58;
			6'd8:  board = 8'd62;  6'd9:  board = 8'd65;  6'd10: board = 8'd69;  6'd11: board = 8'd72;
			6'd12: board = 8'd76;  6'd13: board = 8'd79;  6'd14: board = 8'd83;  6'd15: board = 8'd86;
			6'd16: board = 8'd90;  6'd17: board = 8'd93;  6'd18: board = 8'd97;  6'd19: board = 8'd100;
			6'd20: board = 8'd104; 6'd21: board = 8'd107; 6'd22: board = 8'd111; 6'd23: board = 8'd114;
			6'd24: board = 8'd118; 6'd25: board = 8'd121; 6'd26: board = 8'd125; 6'd27: board = 8'd128;
			6'd28: board = 8'd132; 6'd29: board = 8'd135; 6'd30: board = 8'd139; 6'd31: board = 8'd142;
			6'd32: board = 8'd146; 6'd33: board = 8'd149; 6'd34: board = 8'd153; 6'd35: board = 8'd156;
			6'd36: board = 8'd160; 6'd37: board = 8'd163; 6'd38: board = 8'd167; 6'd39: board = 8'd170;
			6'd40: board = 8'd174; 6'd41: board = 8'd177; 6'd42: board = 8'd181; 6'd43: board = 8'd185;
			6'd44: board = 8'd188; 6'd45: board = 8'd192; 6'd46: board = 8'd195; 6'd47: board = 8'd199;
			6'd48: board = 8'd202; 6'd49: board = 8'd206; 6'd50: board = 8'd209; 6'd51: board = 8'd213;
			6'd52: board = 8'd216; 6'd53: board = 8'd220; 6'd54: board = 8'd223; 6'd55: board = 8'd227;
			6'd56: board = 8'd230; 6'd57: board = 8'd234; 6'd58: board = 8'd237; 6'd59: board = 8'd241;
			6'd60: board = 8'd244; 6'd61: board = 8'd248; 6'd62: board = 8'd251; default: board = 8'd255;
		endcase
	endfunction

	function automatic logic [7:0] gun(input logic [4:0] g, input logic i, input logic m);
		gun = m ? {g, i, g[4:3]} : board({g, i});
	endfunction

	assign red   = gun(irgb[14:10], irgb[15], mame);
	assign green = gun(irgb[9:5],   irgb[15], mame);
	assign blue  = gun(irgb[4:0],   irgb[15], mame);

endmodule
