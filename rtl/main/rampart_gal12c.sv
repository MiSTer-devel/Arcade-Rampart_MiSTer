`timescale 1ns/1ps
//============================================================================
//  GAL16V8 at 12C: the main CPU address decoder.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  Transcribed term for term from the three fuse maps that exist for this
//  socket.  The board build decides which part is fitted:
//      variant 0 = 136082-1006 (set rampart, trackballs:
//                  2 x 64K + 2 x 512K ROMs)
//      variant 1 = 136082-1056 (set rampart2p, joysticks:
//                  2 x 128K + 2 x 512K ROMs)
//      variant 2 = 136082-1005 (sets rampart2pa and rampartj, joysticks:
//                  8 x 128K ROMs)
//  The three differ only in the 10C select codes for 0x000000-0x0FFFFF, that
//  is, in which ROM socket pair answers where.
//
//  Pins (all pin-level, 1 = high):
//      1 /AS   2 A13   3 A14   4 A17   5 A18   6 A19   7 A20   8 A21
//      9 BS0  11 BS1  13 R/W (1 = read)
//     12 /IOSEL  (enables the I/O decoder 11C)
//     14 /SLAPCS (slapstic chip select)
//     15 ROM A13, 16 ROM A14 (the slapstic bank bits replace A13/A14 in
//        0x100000-0x1FFFFF)
//     17, 18, 19  select inputs A, B, C of the memory decoder 10C
//  Every output is combinatorial.
//============================================================================

module rampart_gal12c (
	input  logic [1:0] variant,
	input  logic       i1,  i2,  i3,  i4,  i5,  i6,  i7,  i8,  i9,  i11, i13,
	output logic       o12, o14, o15, o16, o17, o18, o19
);

	// /o12: eight I/O strobe terms, identical in every variant.
	wire n12 = (~i1 &  i2 &  i3 &  i4 &  i5 &  i6 &  i7 &  i8 & ~i13)
	         | (~i1 &  i2 &  i3 &  i4 & ~i5 & ~i6 &  i7 &  i8)
	         | (~i1 & ~i2 & ~i3 & ~i4 &  i5 & ~i7 &  i8 &  i13)
	         | (~i1 & ~i2 & ~i3 & ~i4 &  i5 & ~i6 & ~i7 &  i8)
	         | (~i1 &  i2 &  i3 &  i4 & ~i5 &  i6 &  i7 & ~i8 & ~i13)
	         | (~i2 & ~i3 & ~i4 & ~i5 & ~i6 &  i7 & ~i8)
	         | (~i1 & ~i2 & ~i3 & ~i4 & ~i5 &  i6 & ~i7 & ~i8 & ~i13)
	         | (~i1 & ~i2 & ~i3 &  i4 &  i5 & ~i6 & ~i7 & ~i8);
	assign o12 = ~n12;

	// /o14
	assign o14 = ~(i5 & ~i6 & i7 & ~i8);

	// o15, o16
	assign o15 = (i2 & i8) | (i2 & ~i7) | (i7 & ~i8 & i9);
	assign o16 = (i3 & i8) | (i3 & ~i7) | (i7 & ~i8 & i11);

	// o17: two common terms plus the per-variant A21 = 0 terms.
	wire t17 = (~i1 & ~i2 & ~i3 & ~i4 &  i5 &  i6 &  i7)
	         | (~i1 & ~i4 & ~i5 & ~i6 & ~i7 &  i8)
	         | ( i7 & ~i8);
	always_comb begin
		case (variant)
			2'd0:    o17 = t17 | (i4 & ~i8) | (i5 & ~i8) | (i6 & ~i8);   // 1006
			2'd1:    o17 = t17 | (i5 & ~i8) | (i6 & ~i8);                // 1056
			default: o17 = t17 | (i5 & ~i8);                             // 1005
		endcase
	end

	// o18: two common terms plus one extra term on 1005.
	wire t18 = (~i3 &  i4 &  i5 &  i6 &  i7 &  i8)
	         | (~i1 & ~i2 & ~i3 &  i5 &  i6 &  i7 &  i8);
	assign o18 = t18 | ((variant == 2'd2) & i6 & ~i7 & ~i8);

	// /o19
	assign o19 = i8;

endmodule
