`timescale 1ns/1ps
//============================================================================
//  Rampart (Atari Games, 1990) game core.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  One clk_sys domain (57.272727 MHz) with integer clock enables.  Contents:
//    * rampart_clocks: the enable tree;
//    * the ROM download into SDRAM (loader, SDRAM writer, controller) and the
//      EEPROM save/restore path (rampart_nvram_io);
//    * rampart_main: the 68000 and its bus (decode, program ROM from SDRAM,
//      slapstic, EEPROM, watchdog, IRQ4, latches, switches, LETAs);
//    * rampart_video: bitmap, motion objects, colour RAM, sync;
//    * rampart_sound: YM2413, MSM6295 (ADPCM from SDRAM) and the analogue
//      mix and filters, as one mono signal;
//    * the cabinet controls (from rampart_controls) wired onto the board's
//      switch and LETA lines.
//
//  `pause` (tied low by Arcade-Rampart.sv) stops the 68000 and the sound
//  chips (their clock enables) and holds the VBLANK input of the main board,
//  so the watchdog and IRQ4 wait too; video keeps scanning the frozen RAMs,
//  so the picture stays.
//
//  The parameters are passed down to rampart_main, whose header lists what
//  each one does.  The defaults follow MAME's timing; Arcade-Rampart.sv
//  changes only IRQ_MODEL.  WDOG_FAST_BOOT is for simulation only.
//============================================================================

module rampart_core #(
	parameter int WAIT_MODEL = 0,
	parameter int IRQ_MODEL  = 0,
	parameter int IRQ_H      = -3,
	parameter bit OPEN_BUS   = 1'b0,
	parameter bit SLAP_RESET_ON_BOARD_RESET = 1'b0,
	parameter bit WDOG_FAST_BOOT = 1'b0
)
(
	input  logic        clk_sys,        // 57.272727 MHz
	input  logic        reset,          // OSD / system reset (game side)
	input  logic        init_reset,     // ~pll_locked only (SDRAM, loaders)

	// ---- HPS download / NVRAM ----
	input  logic        ioctl_download,
	input  logic        ioctl_wr,
	input  logic [26:0] ioctl_addr,
	input  logic  [7:0] ioctl_dout,
	input  logic [15:0] ioctl_index,
	output logic        ioctl_wait,
	input  logic        ioctl_upload,
	output logic        ioctl_upload_req,
	output logic  [7:0] ioctl_upload_index,
	output logic  [7:0] ioctl_din,

	// ---- controls (mapped onto the board switch and LETA lines below) ----
	input  logic        coin1,
	input  logic        coin2,
	input  logic        service,        // IN1 SERVICE1
	input  logic        self_test,      // the self-test switch
	input  logic        dip_players3,   // joystick boards: players DIP (1 = 3)
	input  logic        wdog_disable,   // watchdog-disable jumper fitted
	input  logic        dac_mame,       // 0 = board DAC levels, 1 = MAME's
	input  logic        pause,
	input  logic  [3:0] p1_joy,         // {up, down, left, right}
	input  logic  [3:0] p2_joy,
	input  logic  [3:0] p3_joy,
	input  logic  [2:0] p1_btn,         // {start, b2, b1}
	input  logic  [2:0] p2_btn,
	input  logic  [2:0] p3_btn,
	input  logic  [5:0] tb_clk,         // trackball quadrature lines:
	input  logic  [5:0] tb_dir,         //   P1 X, P1 Y, P2 X, P2 Y, P3 X, P3 Y

	// ---- video ----
	output logic        ce_pix,
	output logic  [7:0] vga_r,
	output logic  [7:0] vga_g,
	output logic  [7:0] vga_b,
	output logic        hsync,          // active high
	output logic        vsync,          // active high
	output logic        hblank,
	output logic        vblank,

	// ---- audio ----
	output logic signed [15:0] aud_l,
	output logic signed [15:0] aud_r,

	output logic        rom_loaded,
	output logic  [7:0] cfg_variant,
	output logic  [7:0] cfg_panel,

	// ---- SDRAM pins (SDRAM_CLK is driven by the top level) ----
	inout  wire  [15:0] SDRAM_DQ,
	output logic [12:0] SDRAM_A,
	output logic  [1:0] SDRAM_BA,
	output logic        SDRAM_DQML,
	output logic        SDRAM_DQMH,
	output logic        SDRAM_CKE,
	output logic        SDRAM_nCS,
	output logic        SDRAM_nRAS,
	output logic        SDRAM_nCAS,
	output logic        SDRAM_nWE
);

	// =====================================================================
	//  clock enables
	// =====================================================================
	logic ce_14m, ce_7m, ce_3m58, ce_1m19;
	rampart_clocks u_clocks (
		.clk_sys(clk_sys),
		.ce_14m(ce_14m), .ce_7m(ce_7m), .ce_3m58(ce_3m58), .ce_1m19(ce_1m19)
	);

	// =====================================================================
	//  ROM download into SDRAM
	// =====================================================================
	logic        ld_wr;
	logic [23:0] ld_addr;
	logic  [7:0] ld_data;
	logic        mo_wr;
	logic [16:0] mo_addr;
	logic        wr_busy;

	rampart_rom_loader u_rom_loader (
		.clk(clk_sys), .reset(init_reset),
		.ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr),
		.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout), .ioctl_index(ioctl_index),
		.sdram_wr(ld_wr), .sdram_addr(ld_addr),
		.mo_wr(mo_wr), .mo_addr(mo_addr),
		.rom_data(ld_data),
		.cfg_variant(cfg_variant), .cfg_panel(cfg_panel),
		.rom_loaded(rom_loaded)
	);

	logic        dl_wr, dl_ack;
	logic [23:0] dl_waddr;
	logic [15:0] dl_wdata;

	rampart_sdram_loader #(.AW(24)) u_sdram_loader (
		.clk(clk_sys), .reset(init_reset),
		.ld_wr(ld_wr), .ld_addr(ld_addr), .ld_data(ld_data), .wr_busy(wr_busy),
		.dl_wr(dl_wr), .dl_waddr(dl_waddr), .dl_wdata(dl_wdata), .dl_ack(dl_ack)
	);
	assign ioctl_wait = wr_busy;

	// ---- the SDRAM controller: the download writer, then rampart_main ----
	logic [23:0] sd_addr, m_sd_addr;
	logic [15:0] sd_wdata, sd_rdata;
	logic        sd_we, sd_req, sd_valid, sd_ready;
	logic  [2:0] sd_blen, m_sd_blen;
	logic        m_sd_req, m_rfsh_ok;

	logic        wr_issued;     // the current dl_wr word has been handed over
	wire         wr_go = dl_wr & ~wr_issued & sd_ready;

	always_ff @(posedge clk_sys) begin
		if (init_reset)   wr_issued <= 1'b0;
		else if (wr_go)   wr_issued <= 1'b1;
		else if (!dl_wr)  wr_issued <= 1'b0;
	end
	assign dl_ack   = wr_go;
	assign sd_req   = wr_go | (m_sd_req & ~dl_wr);
	assign sd_we    = wr_go;
	assign sd_addr  = wr_go ? dl_waddr : m_sd_addr;
	assign sd_wdata = dl_wdata;
	assign sd_blen  = wr_go ? 3'd0 : m_sd_blen;

	rampart_sdram u_sdram (
		.clk(clk_sys), .reset(init_reset),
		.addr(sd_addr), .wdata(sd_wdata), .we(sd_we), .blen(sd_blen), .req(sd_req),
		.rdata(sd_rdata), .valid(sd_valid), .ready(sd_ready),
		.rfsh_ok(dl_wr | ioctl_download | m_rfsh_ok),
		.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
		.SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_CKE(SDRAM_CKE),
		.SDRAM_nCS(SDRAM_nCS), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
		.SDRAM_nWE(SDRAM_nWE)
	);

	// =====================================================================
	//  EEPROM save/restore path
	// =====================================================================
	logic        nv_we, nv_seed, nv_end, nv_accepted;
	logic [10:0] nv_addr, nv_dump_addr;
	logic  [7:0] nv_data, nv_dump_data;

	rampart_nvram_io u_nvram_io (
		.clk(clk_sys), .init_reset(init_reset),
		.write_accepted(nv_accepted),
		.ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr),
		.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout), .ioctl_index(ioctl_index),
		.ioctl_upload(ioctl_upload),
		.load_we(nv_we), .load_addr(nv_addr), .load_data(nv_data),
		.seed_we(nv_seed), .load_end(nv_end),
		.dump_addr(nv_dump_addr), .dump_data(nv_dump_data),
		.ioctl_upload_req(ioctl_upload_req), .ioctl_upload_index(ioctl_upload_index),
		.ioctl_din(ioctl_din)
	);

	// =====================================================================
	//  board configuration from the ROM stream
	// =====================================================================
	// 12C part: 0x06 = 136082-1006, 0x56 = 1056, 0x05 = 1005
	wire [1:0] variant = (cfg_variant == 8'h56) ? 2'd1 :
	                     (cfg_variant == 8'h05) ? 2'd2 : 2'd0;
	// input panel: 0 trackball, 1 joystick, 2 joystick (Japanese buttons)
	wire       joy_panel = (cfg_panel != 8'h00);
	wire       jp_panel  = (cfg_panel == 8'h02);

	// The reset counter is cleared while the ROMs are missing or loading,
	// while a saved EEPROM image is loading, and by the OSD reset (the board's
	// reset jumper).
	wire power_on = reset | ~rom_loaded |
	                (ioctl_download & ((ioctl_index == 16'd0) | (ioctl_index == 16'd2)));

	// =====================================================================
	//  switches
	// =====================================================================
	// p*_btn = {start, button 2, button 1}.  The Japanese panel puts the
	// start buttons on the P1/P2 button-2 lines and button 2 on the P3 lines.
	wire firel_n = ~p1_btn[0];
	wire firec_n = ~p2_btn[0];
	wire rotl_n  = jp_panel ? ~p1_btn[2] : ~p1_btn[1];
	wire rotc_n  = jp_panel ? ~p2_btn[2] : ~p2_btn[1];
	wire rotr_n  = jp_panel ? ~p1_btn[1] : ~p3_btn[1];
	wire firer_n = jp_panel ? ~p2_btn[1] : ~p3_btn[0];

	// ---- LETA lines ----
	// Trackball: 12A-1 ch0..3 = P2 Y, P2 X, P1 Y, P1 X; 13A ch0/1 = P3 Y, P3 X.
	// Joystick: both LETAs in TEST mode read the switch lines inverted;
	// p*_joy = {up, down, left, right}, and a closed switch pulls its line low.
	wire [3:0] lo_clk_trk = {tb_clk[0], tb_clk[1], tb_clk[2], tb_clk[3]};
	wire [3:0] lo_dir_trk = {tb_dir[0], tb_dir[1], tb_dir[2], tb_dir[3]};
	wire [3:0] hi_clk_trk = {2'b00, tb_clk[4], tb_clk[5]};
	wire [3:0] hi_dir_trk = {2'b00, tb_dir[4], tb_dir[5]};
	// TEST readout D7..D0 = ~{CLK3,DIR3,CLK2,DIR2,CLK1,DIR1,CLK0,DIR0}
	//   12A-1: D0-D3 = P2 left/right/up/down, D4-D7 = P1 left/right/up/down
	//   13A:   D8-D11 = P3 left/right/up/down, D12-D15 inputs grounded
	wire [3:0] lo_clk_joy = ~{p1_joy[2], p1_joy[0], p2_joy[2], p2_joy[0]};
	wire [3:0] lo_dir_joy = ~{p1_joy[3], p1_joy[1], p2_joy[3], p2_joy[1]};
	wire [3:0] hi_clk_joy = {2'b00, ~p3_joy[2], ~p3_joy[0]};
	wire [3:0] hi_dir_joy = {2'b00, ~p3_joy[3], ~p3_joy[1]};

	// =====================================================================
	//  main board
	// =====================================================================
	logic [16:1] vid_a;
	logic [15:0] vid_din, bm_dout, mo_dout;
	logic  [7:0] cram_dout;
	logic        vid_as, vid_rw, vid_uds_n, vid_lds_n, bmsel_n, mosel_n, cram_n;
	logic        bm_ready, mo_ready, vblank_cpu;
	logic  [8:0] hpos, vpos;
	logic [15:0] latch;
	logic        board_reset;

	// sound-side signals of rampart_main (see the sound block section)
	logic        adpcm_n, yamaha_n, snd_a1, oki_wr, oki_rd, ym_wr, ym_wr_a1;
	logic  [7:0] snd_din, ym_wr_d, oki_dout;
	logic        snd_rom_req, snd_rom_valid;
	logic [23:0] snd_rom_addr;
	logic [15:0] snd_rom_data;

	// pause: the CPU's clock enable stops and the main board's VBLANK holds
	logic        vblank_held;
	always_ff @(posedge clk_sys) if (!pause) vblank_held <= vblank_cpu;
	wire         ce_7m_main   = ce_7m & ~pause;
	wire         vblank_main  = pause ? vblank_held : vblank_cpu;

	/* verilator lint_off UNUSEDSIGNAL */
	logic [23:1] dbg_a;
	logic        dbg_as, dbg_rw, dbg_uds_n, dbg_lds_n, dbg_rom_late, dbg_irq_pending;
	logic  [2:0] dbg_fc;
	logic [15:0] dbg_rdata, dbg_wdata;
	logic  [1:0] dbg_bank;
	/* verilator lint_on UNUSEDSIGNAL */

	rampart_main #(
		.WAIT_MODEL(WAIT_MODEL), .IRQ_MODEL(IRQ_MODEL), .IRQ_H(IRQ_H), .OPEN_BUS(OPEN_BUS),
		.SLAP_RESET_ON_BOARD_RESET(SLAP_RESET_ON_BOARD_RESET),
		.WDOG_FAST_BOOT(WDOG_FAST_BOOT)
	) u_main (
		.clk(clk_sys), .ce_7m(ce_7m_main), .ce_3m58(ce_3m58),
		.init_reset(init_reset), .power_on(power_on), .wdog_disable(wdog_disable),
		.variant(variant),
		.sd_req(m_sd_req), .sd_addr(m_sd_addr), .sd_blen(m_sd_blen),
		.sd_ready(sd_ready & ~dl_wr), .sd_valid(sd_valid), .sd_rdata(sd_rdata),
		.rfsh_ok(m_rfsh_ok),
		.vid_a(vid_a), .vid_din(vid_din), .vid_as(vid_as), .vid_rw(vid_rw),
		.vid_uds_n(vid_uds_n), .vid_lds_n(vid_lds_n),
		.bmsel_n(bmsel_n), .mosel_n(mosel_n), .cram_n(cram_n),
		.bm_dout(bm_dout), .mo_dout(mo_dout), .cram_dout(cram_dout),
		.bm_ready(bm_ready), .mo_ready(mo_ready),
		.hpos(hpos), .vpos(vpos), .vblank(vblank_main),
		.adpcm_n(adpcm_n), .yamaha_n(yamaha_n), .snd_a1(snd_a1), .snd_din(snd_din),
		.oki_wr(oki_wr), .oki_rd(oki_rd), .ym_wr(ym_wr), .ym_wr_a1(ym_wr_a1),
		.ym_wr_d(ym_wr_d), .oki_dout(oki_dout),
		.snd_rom_req(snd_rom_req), .snd_rom_addr(snd_rom_addr),
		.snd_rom_data(snd_rom_data), .snd_rom_valid(snd_rom_valid),
		.latch(latch),
		.firer_n(firer_n), .rotr_n(rotr_n), .firec_n(firec_n), .rotc_n(rotc_n),
		.firel_n(firel_n), .rotl_n(rotl_n),
		.coinl_n(~coin1), .coinr_n(~coin2), .service_n(~service),
		.selftest_n(~self_test), .strap({1'b1, 1'b1, dip_players3}),
		.leta_hi_clk(joy_panel ? hi_clk_joy : hi_clk_trk),
		.leta_hi_dir(joy_panel ? hi_dir_joy : hi_dir_trk),
		.leta_lo_clk(joy_panel ? lo_clk_joy : lo_clk_trk),
		.leta_lo_dir(joy_panel ? lo_dir_joy : lo_dir_trk),
		.nv_load_we(nv_we), .nv_load_addr(nv_addr), .nv_load_data(nv_data),
		.nv_seed_we(nv_seed), .nv_load_end(nv_end),
		.nv_dump_addr(nv_dump_addr), .nv_dump_data(nv_dump_data),
		.nv_write_accepted(nv_accepted),
		.board_reset(board_reset),
		.dbg_a(dbg_a), .dbg_as(dbg_as), .dbg_rw(dbg_rw), .dbg_uds_n(dbg_uds_n),
		.dbg_lds_n(dbg_lds_n), .dbg_fc(dbg_fc), .dbg_rdata(dbg_rdata),
		.dbg_wdata(dbg_wdata), .dbg_rom_late(dbg_rom_late),
		.dbg_irq_pending(dbg_irq_pending), .dbg_bank(dbg_bank)
	);

	// =====================================================================
	//  video
	// =====================================================================
	/* verilator lint_off UNUSEDSIGNAL */
	logic        bm_wait, mo_wait, v32, csync_n, dbg_late;
	logic  [8:0] dbg_idx;
	logic [15:0] dbg_irgb;
	/* verilator lint_on UNUSEDSIGNAL */
	assign bm_ready = ~bm_wait;
	assign mo_ready = ~mo_wait;

	rampart_video #(.WAIT_MODEL(WAIT_MODEL)) u_video (
		.clk_sys(clk_sys), .ce_14m(ce_14m), .ce_7m(ce_7m), .reset(board_reset),
		.cpu_a(vid_a), .cpu_din(vid_din), .cpu_rw(vid_rw), .cpu_as_n(~vid_as),
		.cpu_uds_n(vid_uds_n), .cpu_lds_n(vid_lds_n),
		.bmsel_n(bmsel_n), .mosel_n(mosel_n), .cram_n(cram_n),
		.bm_dout(bm_dout), .mo_dout(mo_dout), .cram_dout(cram_dout),
		.bm_wait(bm_wait), .mo_wait(mo_wait), .cbank(latch[12]),
		.hpos(hpos), .vpos(vpos), .vblank(vblank_cpu), .v32(v32),
		.mo_wr(mo_wr), .mo_addr(mo_addr), .mo_data(ld_data),
		.dac_mame(dac_mame), .ce_pix(ce_pix), .red(vga_r), .green(vga_g), .blue(vga_b),
		.hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank_out(vblank),
		.csync_n(csync_n), .dbg_idx(dbg_idx), .dbg_irgb(dbg_irgb), .dbg_late(dbg_late)
	);

	// =====================================================================
	//  sound
	// =====================================================================
	// The bus strobes come from rampart_main's end-of-cycle record: ym_wr is
	// only raised by a write (the YM2413's /WE is tied low on the board, so a
	// read select must never reach it), and the OKI write carries D15-8 of
	// the same cycle.  The latch bits are 0 /YAMRES, 3-1 YMIX, 4 /PCMRES and
	// 5 PMIX0.
	logic        oki_rom_req;
	logic [17:0] oki_rom_addr;
	logic signed [15:0] audio;
	logic        audio_stb;

	rampart_sound u_sound (
		.clk_sys(clk_sys), .reset(board_reset), .ce_3m58(ce_3m58 & ~pause),
		.ym_cs(ym_wr), .ym_a0(ym_wr_a1), .ym_din(ym_wr_d),
		.oki_wr(oki_wr), .oki_din(ym_wr_d), .oki_dout(oki_dout),
		.yamres_n(latch[0]), .ymix(latch[3:1]), .pcmres_n(latch[4]), .pmix0(latch[5]),
		.oki_rom_req(oki_rom_req), .oki_rom_addr(oki_rom_addr),
		.oki_rom_ack(snd_rom_valid),
		.oki_rom_data(oki_rom_addr[0] ? snd_rom_data[7:0] : snd_rom_data[15:8]),
		.audio(audio), .audio_stb(audio_stb)
	);

	// ADPCM ROM: SDRAM byte 0x420000 + the OKI address, even byte on D15-8.
	// rampart_main starts the read in a gap between program-ROM reads and
	// pulses snd_rom_valid with the word.  The request is masked in the ack
	// clock, where the OKI has not yet dropped it, so no second read starts.
	assign snd_rom_req  = oki_rom_req & ~snd_rom_valid;
	assign snd_rom_addr = 24'h210000 + {7'd0, oki_rom_addr[17:1]};

	// The board's output is mono: the same signal on both channels.
	always_ff @(posedge clk_sys) begin
		if (audio_stb) begin
			aud_l <= audio;
			aud_r <= audio;
		end
	end

	/* verilator lint_off UNUSEDSIGNAL */
	// P3 start (no such button on the board); the live selects and the OKI
	// read strobe (a read has no side effect on the MSM6295); the 1.19 MHz
	// enable (the sound block derives the OKI clock from 1H as the board does).
	wire _unused_core = &{1'b0, p3_btn[2], ce_1m19, latch, adpcm_n, yamaha_n,
	                      snd_a1, snd_din, oki_rd, 1'b0};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
