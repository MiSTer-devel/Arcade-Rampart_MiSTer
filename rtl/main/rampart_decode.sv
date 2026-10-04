`timescale 1ns/1ps
//============================================================================
//  Main CPU address decode: GAL 12C and the two LS138s, 10C and 11C.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  12C sees /AS, R/W, A13, A14, A17-A21 and the slapstic bank bits.  It
//  drives the 10C select code, the I/O enable, the slapstic select and ROM
//  A13/A14.  A15, A16, A22 and A23 never reach 12C.
//
//  10C (memory) is enabled while A22 = 0.  Its select code is 12C pins
//  19/18/17:
//      Y0-Y3  program ROM socket pairs (which pair answers where depends on
//             the 12C variant)
//      Y4     nothing
//      Y5     /BMSEL  bitmap RAM       0x200000-0x21FFFF
//      Y6     /MOSEL  MO / work RAM    0x3E0000-0x3E3FFF, mirrored
//      Y7     /CRAM   colour RAM       0x3C0000-0x3C07FF, mirrored
//  11C (I/O) is enabled while A22 = 1 and 12C pin 12 is low; A21:A19 select:
//      Y0 /ADPCM 0x460000   Y1 /YAMAHA 0x480000   Y2 /EEPROM 0x500000
//      Y3 /UNLOCK 0x5A6000  Y4 /PARALEL 0x640000  Y5 /LETA 0x6C0000
//      Y6 /WDOG 0x726000    Y7 /VACK 0x7E6000
//  Which 12C product terms carry /AS and R/W decides which strobes need
//  them: /MOSEL, /EEPROM, the ROM selects and /SLAPCS do not.  Neither LS138
//  sees /AS itself.
//
//  The ROM word address inside the selected pair is A19..A1 with ROM A14/A13
//  from 12C; each socket ignores the address bits its chips do not have.
//============================================================================

module rampart_decode (
	input  logic [1:0]  variant,     // 12C part: 0 = 1006, 1 = 1056, 2 = 1005
	input  logic [23:1] a,
	input  logic        as_n,
	input  logic        rw,          // 1 = read
	input  logic [1:0]  bs,          // slapstic {BS1, BS0}

	// 10C
	output logic        rom_sel,     // any of Y0-Y3
	output logic [1:0]  rom_pair,    // which of Y0-Y3
	output logic [19:1] rom_a,       // ROM word address, ROM A14/A13 substituted
	output logic        bmsel_n,
	output logic        mosel_n,
	output logic        cram_n,
	// 12C
	output logic        slapcs_n,
	// 11C
	output logic        adpcm_n,
	output logic        yamaha_n,
	output logic        eeprom_n,
	output logic        unlock_n,
	output logic        paralel_n,
	output logic        leta_n,
	output logic        wdog_n,
	output logic        vack_n
);

	logic p12, p14, p15, p16, p17, p18, p19;

	rampart_gal12c u_12c (
		.variant(variant),
		.i1(as_n), .i2(a[13]), .i3(a[14]), .i4(a[17]), .i5(a[18]), .i6(a[19]),
		.i7(a[20]), .i8(a[21]), .i9(bs[0]), .i11(bs[1]), .i13(rw),
		.o12(p12), .o14(p14), .o15(p15), .o16(p16), .o17(p17), .o18(p18), .o19(p19)
	);

	// 10C 74LS138: enabled by /A22; C B A = pins 19 18 17.
	wire       en10 = ~a[22];
	wire [2:0] y10  = {p19, p18, p17};

	assign rom_sel  = en10 & ~y10[2];
	assign rom_pair = y10[1:0];
	assign bmsel_n  = ~(en10 & (y10 == 3'd5));
	assign mosel_n  = ~(en10 & (y10 == 3'd6));
	assign cram_n   = ~(en10 & (y10 == 3'd7));

	assign rom_a    = {a[19:15], p16, p15, a[12:1]};
	assign slapcs_n = p14;

	// 11C 74LS138: enabled by A22 and /IOSEL; C B A = A21 A20 A19.
	wire       en11 = a[22] & ~p12;
	wire [2:0] y11  = a[21:19];

	assign adpcm_n   = ~(en11 & (y11 == 3'd0));
	assign yamaha_n  = ~(en11 & (y11 == 3'd1));
	assign eeprom_n  = ~(en11 & (y11 == 3'd2));
	assign unlock_n  = ~(en11 & (y11 == 3'd3));
	assign paralel_n = ~(en11 & (y11 == 3'd4));
	assign leta_n    = ~(en11 & (y11 == 3'd5));
	assign wdog_n    = ~(en11 & (y11 == 3'd6));
	assign vack_n    = ~(en11 & (y11 == 3'd7));

	/* verilator lint_off UNUSEDSIGNAL */
	wire _unused = &{1'b0, a[23], 1'b0};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
