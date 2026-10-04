`timescale 1ns/1ps
//============================================================================
//  Rampart ROM download router (MiSTer only).
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  Adapted from core/rtl/mem/batman_rom_loader.sv of the Batman MiSTer core
//  (GPL-3.0).
//
//  The index-0 stream IS the SDRAM image: every byte is written to SDRAM at
//  its own stream offset.  Some regions are also copied to block RAM or to
//  registers on the way past.
//
//    stream base  size      contents                           also to
//    0x000000     0x100000  program ROM socket pair on 10C Y0
//    0x100000     0x100000  program ROM socket pair on 10C Y1
//    0x200000     0x100000  program ROM socket pair on 10C Y2
//    0x300000     0x100000  program ROM socket pair on 10C Y3
//    0x400000     0x020000  motion-object graphics ROM (raw)   mo_* (BRAM)
//    0x420000     0x040000  MSM6295 ADPCM ROMs (1007, 1008)
//    0x460000     0x000800  factory EEPROM image               nvram_io
//    0x460800     0x000002  config: 12C variant, input panel   cfg_*
//
//  Each program region holds one socket pair as 16-bit words (even-socket
//  chip on D15:8), starting at the region base; the rest is 0xFF.  Which
//  CPU addresses select which pair is decided by the 12C GAL, which differs
//  between board variants, so the config byte names the variant:
//    0x06 = 136082-1006, 0x56 = 136082-1056, 0x05 = 136082-1005.
//
//  Outputs are registered.  `rom_loaded` rises when the index-0 download
//  ends; an NVRAM (index 2) load never sets it.
//============================================================================

module rampart_rom_loader
(
	input  logic        clk,
	input  logic        reset,          // ~pll_locked only (never the game reset)

	// ---- HPS ioctl download channel ----
	input  logic        ioctl_download,
	input  logic        ioctl_wr,
	input  logic [26:0] ioctl_addr,     // byte offset into the index-0 stream
	input  logic  [7:0] ioctl_dout,
	input  logic [15:0] ioctl_index,

	// ---- every stream byte, with its SDRAM byte address ----
	output logic        sdram_wr,
	output logic [23:0] sdram_addr,

	// ---- motion-object graphics ROM -> block RAM ----
	output logic        mo_wr,
	output logic [16:0] mo_addr,        // 0..0x1FFFF

	// shared data byte for every destination
	output logic  [7:0] rom_data,

	// ---- config bytes ----
	output logic  [7:0] cfg_variant,    // 12C GAL variant code
	output logic  [7:0] cfg_panel,      // 0 trackball, 1 joystick, 2 joystick (Japan)

	// ---- high once the index-0 download has ended ----
	output logic        rom_loaded
);

	localparam [26:0] BASE_MO    = 27'h400000;
	localparam [26:0] BASE_ADPCM = 27'h420000;
	localparam [26:0] BASE_CFG   = 27'h460800;
	localparam [26:0] END_STREAM = 27'h460802;

	wire is_idx0 = (ioctl_index == 16'd0);
	wire wr      = ioctl_download & ioctl_wr & is_idx0 & ~reset;
	wire in_img  = wr & (ioctl_addr < END_STREAM);
	wire in_mo   = (ioctl_addr >= BASE_MO) & (ioctl_addr < BASE_ADPCM);

	always_ff @(posedge clk) begin
		rom_data   <= ioctl_dout;
		sdram_wr   <= in_img;
		mo_wr      <= in_img & in_mo;
		sdram_addr <= ioctl_addr[23:0];
		mo_addr    <= ioctl_addr[16:0];
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			cfg_variant <= 8'h00;
			cfg_panel   <= 8'h00;
		end else if (in_img && ioctl_addr == BASE_CFG) begin
			cfg_variant <= ioctl_dout;
		end else if (in_img && ioctl_addr == BASE_CFG + 27'd1) begin
			cfg_panel   <= ioctl_dout;
		end
	end

	// rom_loaded rises on the falling edge of the index-0 download.
	wire  dl0 = ioctl_download & is_idx0;
	logic dl0_d;
	always_ff @(posedge clk) begin
		if (reset) begin
			dl0_d      <= 1'b0;
			rom_loaded <= 1'b0;
		end else begin
			dl0_d <= dl0;
			if (dl0)        rom_loaded <= 1'b0;   // a download is in progress
			else if (dl0_d) rom_loaded <= 1'b1;   // the first cycle after it ends
		end
	end

endmodule
