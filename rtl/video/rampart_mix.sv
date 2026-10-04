`timescale 1ns/1ps
//============================================================================
//  Rampart playfield / motion-object priority (two LS157s at 1/2J and 2H).
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  The priority PAL socket at 2J is empty on production boards, so the mux
//  takes the motion object whenever its pen is not 0.  Playfield pen 0 is an
//  ordinary colour.  Colour index: MO = 0x100 + 16 x COLOUR + pen,
//  playfield = its 8-bit pixel.
//============================================================================

module rampart_mix (
	input  logic [7:0] pf_pix,
	input  logic [7:0] mo_pix,     // {COLOUR, pen}
	output logic [8:0] idx
);

	assign idx = (mo_pix[3:0] != 4'h0) ? {1'b1, mo_pix} : {1'b0, pf_pix};

endmodule
