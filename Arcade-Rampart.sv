//============================================================================
//
//  Rampart (Atari Games, 1990) MiSTer FPGA core: top-level glue.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  Adapted from Arcade-Batman.sv of the Batman MiSTer core (GPL-3.0), itself
//  from the Skull & Crossbones, Bad Lands, Vindicators, Xybots and
//  Blasteroids cores.
//
//  Connects rampart_core (the game PCB in one clk_sys domain with integer
//  clock enables) to the MiSTer framework: PLL, hps_io (ROM download, NVRAM,
//  controls), analog alignment, arcade_video, audio and the SDRAM pins.
//  clk_sys = 57.272727 MHz = 4 x the 14.318181 MHz crystal; the pixel clock
//  is clk_sys/8 = 7.159 MHz, giving a 456 x 262 raster with 336 x 240
//  visible on a horizontal monitor.
//
//  Controls.  The trackball board (set `rampart`) has three trackballs with
//  Fire and Rotate buttons; the joystick boards (`rampart2p`, `rampart2pa`,
//  `rampartj`) have three 4-way joysticks with the same two buttons and a
//  players strap.  rtl/rampart_controls.sv maps the MiSTer pads, mouse,
//  spinners, paddles and analog sticks onto them; the MRA's config byte tells
//  the core which panel the set has, and the OSD hides the options that do
//  not apply.  Game settings live in the 2816 EEPROM, saved as NVRAM on ioctl
//  index 2 (2048 bytes).  The MRA also carries MAME's factory EEPROM image,
//  used when there is no save yet.
//
//============================================================================

`timescale 1ns/1ps

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1        = 0;
assign VGA_SCALER    = 0;
assign VGA_DISABLE   = 0;
assign HDMI_FREEZE   = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT= 0;
assign FB_FORCE_BLANK= 0;

assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

//////////////////////////////////////////////////////////////////

// Horizontal cabinet: the native raster is 336 x 240 on a 4:3 monitor.
wire  [1:0] ar  = status[122:121];
wire [11:0] arx = (ar == 2'd0) ? 12'd4 : 12'(ar - 1'd1);
wire [11:0] ary = (ar == 2'd0) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"Rampart;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[4],Orientation,Original,Flip;",
	"O[22:20],Scale,Normal,V-Integer,HV-Integer,Narrower HV-Integer;",
	"-;",
	// Analog alignment (CRT H-Size / H-Position, VGA H-Shift / V-Shift), the
	// same page as the other Atari MiSTer cores (rampart_analog_adjust.sv).
	"P1,Analog alignment;",
	"P1-;",
	"P1O[27:23],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[34:28],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,+49,+50,+51,+52,+53,+54,+55,+56,+57,+58,+59,+60,+61,+62,+63,-64,-63,-62,-61,-60,-59,-58,-57,-56,-55,-54,-53,-52,-51,-50,-49,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[40:35],Analog VGA H-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[46:41],Analog VGA V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	// Colour DAC: the board's resistor network (default) or MAME's linear table.
	"O[8],Colour levels,Board DAC,MAME;",
	"-;",
	// Controls.  "H0" items are hidden on the joystick boards, "h0" items on
	// the trackball board (status_menumask bit 0).
	"H0O[13:10],Trackball speed,1x,1.125x,1.25x,1.375x,1.5x,1.75x,2x,2.5x,3x,4x,0.25x,0.375x,0.5x,0.625x,0.75x,0.875x;",
	"H0O[14],Trackball X,Normal,Inverted;",
	"H0O[15],Trackball Y,Normal,Inverted;",
	"h0O[16],Joysticks,4-way,8-way;",
	"h0O[17],Players,3,2;",
	"-;",
	// The SELF TEST switch on the board.
	"O[6],Service,Off,On;",
	// The watchdog-disable jumper (a board test aid; the game needs none).
	"O[9],Watchdog,Enabled,Disabled;",
	"-;",
	"T[0],Reset;",
	// The J1 list is the pad order.  Each MRA's <buttons> element names the
	// buttons Main asks for when mapping, taken from the front of this list.
	// Fire and Rotate are the board's FIRE / ROT buttons.  Player 3's Coin is
	// the SERVICE (service credit) input.  Start is last because only the
	// Japanese board has start buttons; the other MRAs leave it out.
	"J1,Fire,Rotate,Coin,Start;",
	"jn,A,B,Select,Start;",
	"V,v",`BUILD_DATE
};

wire        forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;
wire        direct_video;
wire [21:0] gamma_bus;

wire        ioctl_download;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire [15:0] ioctl_index;
wire        ioctl_wait;
wire        ioctl_upload, ioctl_upload_req;
wire  [7:0] ioctl_upload_index, ioctl_din;

wire [31:0] joystick_0, joystick_1, joystick_2;
wire [15:0] joystick_l_analog_0, joystick_l_analog_1, joystick_l_analog_2;
wire  [8:0] spinner_0, spinner_1, spinner_2;
wire  [7:0] paddle_0, paddle_1, paddle_2;

// The input panel code from the MRA's config byte: 0 trackball, else joystick.
wire  [7:0] core_cfg_panel;
wire        joy_panel = (core_cfg_panel != 8'h00);

// ============================================================================
//  The index-0 ROM download stream (the MRA's part order must match)
// ============================================================================
// Decoded by rampart_rom_loader.sv; every byte lands in SDRAM at its stream
// offset.  10C is the board's memory decoder; its outputs Y0-Y3 select the
// four program-ROM socket pairs.  These localparams are unused here; they
// keep the map visible at the top of the core for checking against the MRA.
//
//   stream base  size       contents
//   0x000000     0x100000   program ROM socket pair selected by 10C Y0
//   0x100000     0x100000   program ROM socket pair selected by 10C Y1
//   0x200000     0x100000   program ROM socket pair selected by 10C Y2
//   0x300000     0x100000   program ROM socket pair selected by 10C Y3
//   0x400000     0x020000   motion-object graphics ROM, raw bytes
//   0x420000     0x040000   MSM6295 ADPCM ROMs
//   0x460000     0x000800   factory EEPROM image (first boot only)
//   0x460800     0x000002   12C GAL variant code, input panel code
//   (index 2)    0x000800   2816 EEPROM, NVRAM save/restore
localparam [26:0] ROM_SZ_PROG     = 27'h400000;   // stream 0x000000
localparam [26:0] ROM_SZ_MO       = 27'h020000;   // stream 0x400000
localparam [26:0] ROM_SZ_ADPCM    = 27'h040000;   // stream 0x420000
localparam [26:0] NVRAM_SZ_EEPROM = 27'h000800;   // ioctl index 2

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),

	.buttons(buttons),
	.status(status),
	.status_menumask({15'd0, joy_panel}),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait),

	// NVRAM: the 2816 image, index 2, 2048 bytes.
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_upload_index(ioctl_upload_index),
	.ioctl_din(ioctl_din),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_2(joystick_2),
	.joystick_l_analog_0(joystick_l_analog_0),
	.joystick_l_analog_1(joystick_l_analog_1),
	.joystick_l_analog_2(joystick_l_analog_2),
	.spinner_0(spinner_0), .spinner_1(spinner_1), .spinner_2(spinner_2),
	.paddle_0(paddle_0), .paddle_1(paddle_1), .paddle_2(paddle_2),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;               // 57.272727 MHz
wire clk_sdram;             // same rate, phase-shifted for the SDRAM_CLK pin
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(1'b0),
	.outclk_0(clk_sys),
	.outclk_1(clk_sdram),
	.locked(pll_locked)
);

// SDRAM clock pin from the phase-shifted PLL output (rtl/pll/pll_0002.v).
assign SDRAM_CLK = clk_sdram;

// `reset` is the OSD / system reset for the game.  `~pll_locked` alone is
// init_reset, the only reset the SDRAM controller may see.
wire reset = RESET | status[0] | buttons[1] | ~pll_locked;

///////////////////////   CONTROLS   /////////////////////////////

wire [3:0] p1_joy, p2_joy, p3_joy;
wire [2:0] p1_btn, p2_btn, p3_btn;
wire       coin1, coin2, service;
wire [5:0] tb_clk, tb_dir;

rampart_controls u_controls
(
	.clk(clk_sys), .reset(~pll_locked), .pause(1'b0),
	.joy_0(joystick_0), .joy_1(joystick_1), .joy_2(joystick_2),
	.ana_0(joystick_l_analog_0), .ana_1(joystick_l_analog_1), .ana_2(joystick_l_analog_2),
	.spin_0(spinner_0), .spin_1(spinner_1), .spin_2(spinner_2),
	.pad_0(paddle_0), .pad_1(paddle_1), .pad_2(paddle_2),
	.ps2_mouse(ps2_mouse),
	.sens(status[13:10]), .inv_x(status[14]), .inv_y(status[15]), .joy8(status[16]),
	.p1_joy(p1_joy), .p2_joy(p2_joy), .p3_joy(p3_joy),
	.p1_btn(p1_btn), .p2_btn(p2_btn), .p3_btn(p3_btn),
	.coin1(coin1), .coin2(coin2), .service(service),
	.tb_clk(tb_clk), .tb_dir(tb_dir)
);

wire self_test    = status[6];
wire dip_players3 = ~status[17];
wire wdog_disable = status[9];
wire dac_mame     = status[8];

///////////////////////   CORE   /////////////////////////////////

wire        ce_pix;
wire  [7:0] core_r, core_g, core_b;
wire        core_hs, core_vs, core_hb, core_vb;
wire        core_rom_loaded;
wire  [7:0] core_cfg_variant;
wire signed [15:0] aud_l, aud_r;

// The frame interrupt uses the flip-flop circuit Atari drew for the sibling
// Klax board (set by VBLANK or 32V, cleared by the acknowledge write).
// IRQ_MODEL 0 is MAME's timing instead (see rtl/main/rampart_irq.sv).
rampart_core #(.IRQ_MODEL(1)) u_core
(
	.clk_sys(clk_sys), .reset(reset), .init_reset(~pll_locked),

	.ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout), .ioctl_index(ioctl_index), .ioctl_wait(ioctl_wait),
	.ioctl_upload(ioctl_upload), .ioctl_upload_req(ioctl_upload_req),
	.ioctl_upload_index(ioctl_upload_index), .ioctl_din(ioctl_din),

	.coin1(coin1), .coin2(coin2), .service(service), .self_test(self_test),
	.dip_players3(dip_players3), .wdog_disable(wdog_disable), .dac_mame(dac_mame),
	.pause(1'b0),
	.p1_joy(p1_joy), .p2_joy(p2_joy), .p3_joy(p3_joy),
	.p1_btn(p1_btn), .p2_btn(p2_btn), .p3_btn(p3_btn),
	.tb_clk(tb_clk), .tb_dir(tb_dir),

	.ce_pix(ce_pix), .vga_r(core_r), .vga_g(core_g), .vga_b(core_b),
	.hsync(core_hs), .vsync(core_vs), .hblank(core_hb), .vblank(core_vb),

	.aud_l(aud_l), .aud_r(aud_r),
	.rom_loaded(core_rom_loaded),
	.cfg_variant(core_cfg_variant), .cfg_panel(core_cfg_panel),

	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH), .SDRAM_CKE(SDRAM_CKE), .SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_nWE(SDRAM_nWE)
);

///////////////////////   AUDIO   ////////////////////////////////

// The board's audio output is MONO; both channels carry one signal.
assign AUDIO_S = 1'b1;              // signed samples
assign AUDIO_L = aud_l;
assign AUDIO_R = aud_r;

///////////////////////   VIDEO   ////////////////////////////////

wire [7:0] adj_r, adj_g, adj_b;
wire       adj_hs, adj_vs, adj_hb, adj_vb, adj_ce;

// H_TOTAL is in ce_pix ticks: 456 pixels per line, 262 lines, and ce_pix is
// ce_7m = clk_sys/8 (CLK_PER_PIX = 8).
rampart_analog_adjust #(.H_TOTAL(456), .V_TOTAL(262), .CLK_PER_PIX(8)) u_analog_adjust
(
	.clk        (clk_sys),
	.ce_pix     (ce_pix),
	.osd_hsize  (status[27:23]),
	.osd_hpos   (status[34:28]),
	.osd_hshift (status[40:35]),
	.osd_vshift (status[46:41]),
	.r_in(core_r), .g_in(core_g), .b_in(core_b),
	.hs_in(core_hs), .vs_in(core_vs), .hb_in(core_hb), .vb_in(core_vb),
	.r_out(adj_r), .g_out(adj_g), .b_out(adj_b),
	.hs_out(adj_hs), .vs_out(adj_vs), .hb_out(adj_hb), .vb_out(adj_vb),
	.ce_out(adj_ce)
);

wire [2:0] fx = 3'b000;

wire       rotate_ccw = 1'b0;
wire       no_rotate  = 1'b1;
wire       flip       = status[4] & ~direct_video;
wire       video_rotated;

wire vga_de_raw;

// 336 pixels wide, 24-bit RGB, one pixel per 7M clock.
arcade_video #(.WIDTH(336), .DW(24)) arcade_video
(
	.clk_video (clk_sys),
	.ce_pix    (adj_ce),
	.RGB_in    ({adj_r, adj_g, adj_b}),
	.HBlank    (adj_hb),
	.VBlank    (adj_vb),
	.HSync     (adj_hs),
	.VSync     (adj_vs),

	.CLK_VIDEO (CLK_VIDEO),
	.CE_PIXEL  (CE_PIXEL),
	.VGA_R     (VGA_R),
	.VGA_G     (VGA_G),
	.VGA_B     (VGA_B),
	.VGA_HS    (VGA_HS),
	.VGA_VS    (VGA_VS),
	.VGA_DE    (vga_de_raw),
	.VGA_SL    (VGA_SL),

	.fx                 (fx),
	.forced_scandoubler (forced_scandoubler),
	.gamma_bus          (gamma_bus)
);

// video_freak SCALE encoding: 0 normal, 1 V-integer, 2 HV-Integer-, 4 HV-Integer.
wire [2:0] scale_sel = (status[22:20] == 3'd0) ? 3'd0 :
                       (status[22:20] == 3'd1) ? 3'd1 :
                       (status[22:20] == 3'd2) ? 3'd4 :
                                                 3'd2;

video_freak video_freak
(
	.CLK_VIDEO  (CLK_VIDEO),
	.CE_PIXEL   (CE_PIXEL),
	.VGA_VS     (VGA_VS),
	.HDMI_WIDTH (HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE     (VGA_DE),
	.VIDEO_ARX  (VIDEO_ARX),
	.VIDEO_ARY  (VIDEO_ARY),
	.VGA_DE_IN  (vga_de_raw),
	.ARX        (arx),
	.ARY        (ary),
	.CROP_SIZE  (12'd0),
	.CROP_OFF   (5'd0),
	.SCALE      (scale_sel)
);

screen_rotate screen_rotate (.*);

///////////////////////   STATUS LED   ///////////////////////////

assign LED_USER = ioctl_download;

// Unused outputs and the map constants above, tied off for lint.
/* verilator lint_off UNUSEDSIGNAL */
wire _unused_emu = &{1'b0, core_rom_loaded, core_cfg_variant, ps2_key,
                     ROM_SZ_PROG, ROM_SZ_MO, ROM_SZ_ADPCM, NVRAM_SZ_EEPROM, 1'b0};
/* verilator lint_on UNUSEDSIGNAL */

endmodule
