`timescale 1ns/1ps
//============================================================================
//  Rampart main board: the 68000 and everything on its bus except the video
//  RAMs and the sound chips.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  Contents: fx68k, the 12C/10C/11C address decode, /DTACK and /VPA, the
//  program ROM (from SDRAM), the slapstic, the EEPROM and its unlock flop,
//  the watchdog / reset counter, IRQ4, the output latches, the switch inputs
//  and the two LETAs.  The bitmap, colour and MO RAMs are in the video block,
//  which sees the live CPU bus through the vid_* ports.  The YM2413 and the
//  MSM6295 are in the sound block, which gets the snd_* ports.
//
//  Options (see the modules for detail):
//    WAIT_MODEL  0 = no wait states, 1 = estimated board wait states
//    IRQ_MODEL   0 = IRQ4 at lines 0/64/128/192/256, 1 = 64/128/192/240
//    IRQ_H       model 0: H count of the request (see rampart_irq)
//    OPEN_BUS    0 = unmapped reads 0 and undriven switch bits 1,
//                1 = every undriven data bit reads 1
//    SLAP_RESET_ON_BOARD_RESET  1 = board reset also resets the slapstic
//    WDOG_FAST_BOOT             1 = skip the eight-frame power-on reset
//    EE_T_WR     EEPROM busy time after a write, in clk_sys
//============================================================================

module rampart_main #(
	parameter int WAIT_MODEL = 0,
	parameter int IRQ_MODEL  = 0,
	parameter int IRQ_H      = -3,
	parameter bit OPEN_BUS   = 1'b0,
	parameter bit SLAP_RESET_ON_BOARD_RESET = 1'b0,
	parameter bit WDOG_FAST_BOOT = 1'b0,
	parameter int EE_T_WR    = 0
) (
	input  logic        clk,            // clk_sys, 57.272727 MHz
	input  logic        ce_7m,
	input  logic        ce_3m58,        // LETA clock edge (/1H rising)
	input  logic        init_reset,     // FPGA / PLL
	input  logic        power_on,       // 7D /CLR: power-on, reset jumper, ROM not loaded
	input  logic        wdog_disable,   // JMP1 fitted

	input  logic  [1:0] variant,        // 12C part: 0 = 1006, 1 = 1056, 2 = 1005

	// ---- SDRAM host port (program ROM and ADPCM) ----
	output logic        sd_req,
	output logic [23:0] sd_addr,
	output logic  [2:0] sd_blen,
	input  logic        sd_ready,
	input  logic        sd_valid,
	input  logic [15:0] sd_rdata,
	output logic        rfsh_ok,

	// ---- video block: live CPU bus and the RAM selects ----
	output logic [16:1] vid_a,
	output logic [15:0] vid_din,
	output logic        vid_as,
	output logic        vid_rw,
	output logic        vid_uds_n,
	output logic        vid_lds_n,
	output logic        bmsel_n,
	output logic        mosel_n,
	output logic        cram_n,
	input  logic [15:0] bm_dout,
	input  logic [15:0] mo_dout,
	input  logic  [7:0] cram_dout,
	input  logic        bm_ready,
	input  logic        mo_ready,
	input  logic  [8:0] hpos,
	input  logic  [8:0] vpos,
	input  logic        vblank,

	// ---- sound block ----
	output logic        adpcm_n,        // MSM6295 select (live)
	output logic        yamaha_n,       // YM2413 select (live)
	output logic        snd_a1,         // YM2413 A0 = CPU A1
	output logic  [7:0] snd_din,        // D15-8
	output logic        oki_wr,         // 1-clk: end of a write to the MSM6295
	output logic        oki_rd,         // 1-clk: end of a read of the MSM6295
	output logic        ym_wr,          // 1-clk: end of a write to the YM2413
	output logic        ym_wr_a1,       // A1 of that write (0 = address, 1 = data)
	output logic  [7:0] ym_wr_d,        // data of that write
	input  logic  [7:0] oki_dout,       // MSM6295 status, read on D15-8
	input  logic        snd_rom_req,    // ADPCM read request (held until valid)
	input  logic [23:0] snd_rom_addr,   // SDRAM word address
	output logic [15:0] snd_rom_data,
	output logic        snd_rom_valid,

	// ---- latch 7B/6C ----
	output logic [15:0] latch,

	// ---- switches (board line levels, 0 = pressed) ----
	input  logic        firer_n, rotr_n, firec_n, rotc_n, firel_n, rotl_n,
	input  logic        coinl_n, coinr_n, service_n, selftest_n,
	input  logic  [2:0] strap,
	// ---- LETA inputs: 13A drives D15-8, 12A-1 drives D7-0 ----
	input  logic  [3:0] leta_hi_clk, leta_hi_dir,
	input  logic  [3:0] leta_lo_clk, leta_lo_dir,

	// ---- EEPROM load/save (rampart_nvram_io) ----
	input  logic        nv_load_we,
	input  logic [10:0] nv_load_addr,
	input  logic  [7:0] nv_load_data,
	input  logic        nv_seed_we,
	input  logic        nv_load_end,
	input  logic [10:0] nv_dump_addr,
	output logic  [7:0] nv_dump_data,
	output logic        nv_write_accepted,

	// ---- board /RESET (to the video and sound blocks) ----
	output logic        board_reset,
	// ---- debug taps for simulation ----
	output logic [23:1] dbg_a,
	output logic        dbg_as,
	output logic        dbg_rw,
	output logic        dbg_uds_n,
	output logic        dbg_lds_n,
	output logic  [2:0] dbg_fc,
	output logic [15:0] dbg_rdata,
	output logic [15:0] dbg_wdata,
	output logic        dbg_rom_late,
	output logic        dbg_irq_pending,
	output logic  [1:0] dbg_bank
);

	// =====================================================================
	//  CPU
	// =====================================================================
	logic [23:1] a;
	logic [15:0] wdata, rdata;
	logic        as, uds_n, lds_n, rw, dtack, vpa_n, en_phi1, en_phi2;
	logic  [2:0] fc, ipl_n;
	logic        cpu_reset;

	assign cpu_reset = init_reset | board_reset;

	/* verilator lint_off UNUSEDSIGNAL */
	logic reset_inst;
	/* verilator lint_on UNUSEDSIGNAL */

	rampart_cpu u_cpu (
		.clk(clk), .ce_7m(ce_7m), .reset(cpu_reset), .ipl_n(ipl_n),
		.a(a), .wdata(wdata), .rdata(rdata), .as(as), .uds_n(uds_n), .lds_n(lds_n),
		.rw(rw), .dtack(dtack), .vpa_n(vpa_n), .fc(fc), .reset_inst(reset_inst),
		.en_phi1(en_phi1), .en_phi2(en_phi2)
	);

	// =====================================================================
	//  decode
	// =====================================================================
	logic [1:0]  bank;
	logic        rom_sel, slapcs_n, yamaha_n_i, eeprom_n, unlock_n, paralel_n,
	             leta_n, wdog_n, vack_n;
	logic [1:0]  rom_pair;
	logic [19:1] rom_a;

	rampart_decode u_decode (
		.variant(variant), .a(a), .as_n(~as), .rw(rw), .bs(bank),
		.rom_sel(rom_sel), .rom_pair(rom_pair), .rom_a(rom_a),
		.bmsel_n(bmsel_n), .mosel_n(mosel_n), .cram_n(cram_n), .slapcs_n(slapcs_n),
		.adpcm_n(adpcm_n), .yamaha_n(yamaha_n_i), .eeprom_n(eeprom_n),
		.unlock_n(unlock_n), .paralel_n(paralel_n), .leta_n(leta_n),
		.wdog_n(wdog_n), .vack_n(vack_n)
	);
	assign yamaha_n = yamaha_n_i;

	// =====================================================================
	//  bus-cycle record: what the cycle was, kept until /AS rises
	// =====================================================================
	logic        as_d;
	logic [14:1] c_a;
	logic        c_rw, c_uds, c_lds, c_slapcs, c_paralel, c_eeprom, c_unlock,
	             c_yamaha, c_adpcm, c_romrd;
	logic [15:0] c_wd;
	logic [11:0] as_age;       // clk_sys since /AS asserted
	logic [11:0] idle_age;     // clk_sys since /AS last asserted
	logic  [1:0] c_ph1;        // CPU clock rising edges seen while /AS is low

	wire cyc_start = as & ~as_d;
	wire cyc_end   = ~as & as_d;

	always_ff @(posedge clk) begin
		as_d <= as;
		if (as) begin
			c_a  <= a[14:1];  c_rw <= rw;  c_wd <= wdata;
			c_slapcs  <= ~slapcs_n;
			c_paralel <= ~paralel_n;
			c_eeprom  <= ~eeprom_n;
			c_unlock  <= ~unlock_n;
			c_yamaha  <= ~yamaha_n_i;
			c_adpcm   <= ~adpcm_n;
			if (!uds_n) c_uds <= 1'b1;
			if (!lds_n) c_lds <= 1'b1;
			if (cyc_start) c_romrd <= rom_sel & rw;
			if (as_age != 12'hFFF) as_age <= as_age + 12'd1;
			if (en_phi1 && c_ph1 != 2'd3) c_ph1 <= c_ph1 + 2'd1;
		end else begin
			c_uds <= 1'b0; c_lds <= 1'b0; as_age <= 12'd0; c_ph1 <= 2'd0;
		end
		if (cyc_start)               idle_age <= 12'd0;
		else if (idle_age != 12'hFFF) idle_age <= idle_age + 12'd1;
	end

	wire c_wr = cyc_end & ~c_rw;

	// =====================================================================
	//  program ROM (SDRAM)
	// =====================================================================
	logic [15:0] rom_data;
	logic        rom_ready;

	// Refresh and ADPCM reads may start only while the current cycle no
	// longer needs the SDRAM and the next /AS is far enough away that the
	// next ROM read still gets its word before /DTACK is sampled.  A ROM
	// word takes 9 clk_sys from /AS and is sampled at 12, so an operation
	// that starts at s must end by (next /AS + 3).  The longest one is an
	// ADPCM read (10 clk_sys) or a refresh (6); only one starts per window
	// opening unless the window is still open when the first one ends.
	//
	// In a bus cycle, once its ROM word (if any) has arrived: /AS rises on
	// a CPU clock falling edge and the next bus cycle's /AS falls at the
	// earliest 1.5 CPU clocks later, so while /AS is low the next /AS is at
	// least 12 clk_sys away.  This holds for cycles of any length, including
	// interrupt acknowledges with /VPA.
	//
	// Between bus cycles (long internal operations such as DIVS): the 68000
	// starts a bus cycle only at a microcycle boundary (every second CPU
	// clock), and /AS falls one CPU clock later, so /AS can fall only on
	// every second CPU clock rising edge.  Those edges are found from the
	// last /AS edge.  In the 3 clk_sys after such an edge with /AS still
	// high, the next /AS is 16 clk_sys away: an operation started there ends
	// by 3 + 10 = 13, before 16 + 3.  A cycle that was longer than four
	// clocks (an interrupt acknowledge with /VPA, a wait state, a
	// read-modify-write) may have moved the microcycle grid, so the grid is
	// trusted again only from the next /AS edge.
	//
	// A CPU in reset opens the window, and so does one that has made no bus
	// cycle for 4 095 clk_sys with the grid unknown (STOP).
	logic       grid_ok;       // cap_edge is known
	logic       cap_edge;      // the last CPU clock rising edge may start /AS
	logic [2:0] ph1_d;         // en_phi1 delayed by 1, 2, 3 clk_sys
	always_ff @(posedge clk) begin
		ph1_d <= {ph1_d[1:0], en_phi1};
		if (cyc_start)    cap_edge <= 1'b1;
		else if (en_phi1) cap_edge <= ~cap_edge;
		if (cpu_reset)                     grid_ok <= 1'b0;
		else if (cyc_start)                grid_ok <= 1'b1;
		else if (cyc_end && c_ph1 != 2'd2) grid_ok <= 1'b0;
	end
	wire idle_ok = !as && grid_ok && cap_edge && (ph1_d != 3'd0);

	wire start_ok = cpu_reset
	              | (as && as_age != 12'd0 && (!c_romrd || rom_ready))
	              | idle_ok
	              | (!as && idle_age == 12'hFFF);

	rampart_prog_rom #(.AW(24)) u_prog_rom (
		.clk(clk), .reset(init_reset), .variant(variant),
		.cpu_req(cyc_start & rom_sel & rw), .pair(rom_pair), .rom_a(rom_a),
		.cpu_data(rom_data), .cpu_ready(rom_ready), .start_ok(start_ok),
		.snd_req(snd_rom_req), .snd_addr(snd_rom_addr),
		.snd_data(snd_rom_data), .snd_valid(snd_rom_valid),
		.sd_req(sd_req), .sd_addr(sd_addr), .sd_blen(sd_blen), .sd_ready(sd_ready),
		.sd_valid(sd_valid), .sd_rdata(sd_rdata), .rfsh_ok(rfsh_ok)
	);

	// =====================================================================
	//  /DTACK, /VPA
	// =====================================================================
	rampart_dtack #(.WAIT_MODEL(WAIT_MODEL)) u_dtack (
		.clk(clk), .en_phi2(en_phi2), .as(as), .fc(fc),
		.rom_sel(rom_sel & rw & ~cyc_start), .rom_ready(rom_ready),
		.bmsel_n(bmsel_n), .mosel_n(mosel_n), .eeprom_n(eeprom_n), .adpcm_n(adpcm_n),
		.yamaha_n(yamaha_n_i), .leta_n(leta_n),
		.bm_ready(bm_ready), .mo_ready(mo_ready),
		.dtack(dtack), .vpa_n(vpa_n), .rom_late(dbg_rom_late)
	);

	// =====================================================================
	//  slapstic 137412-118: one clock per bus cycle, at its end
	// =====================================================================
	/* verilator lint_off UNUSEDSIGNAL */
	logic [3:0] slap_state;
	/* verilator lint_on UNUSEDSIGNAL */

	rampart_slapstic #(.SLAP_RESET_ON_BOARD_RESET(SLAP_RESET_ON_BOARD_RESET)) u_slapstic (
		.clk(clk), .power_on(init_reset), .board_reset(board_reset),
		.cyc(cyc_end), .cs_n(~c_slapcs), .a(c_a[14:1]),
		.bank(bank), .dbg_state(slap_state)
	);

	// =====================================================================
	//  reset counter / watchdog, IRQ4
	// =====================================================================
	/* verilator lint_off UNUSEDSIGNAL */
	logic [3:0] wd_count;
	/* verilator lint_on UNUSEDSIGNAL */

	rampart_watchdog #(.FAST_BOOT(WDOG_FAST_BOOT)) u_watchdog (
		.clk(clk), .power_on(power_on | init_reset), .jmp1(wdog_disable),
		.wdog(~wdog_n), .vblank(vblank), .board_reset(board_reset), .count(wd_count)
	);

	rampart_irq #(.IRQ_MODEL(IRQ_MODEL), .IRQ_H(IRQ_H)) u_irq (
		.clk(clk), .reset(cpu_reset), .ce_7m(ce_7m), .hpos(hpos), .vpos(vpos),
		.vblank(vblank), .vack(~vack_n), .pending(dbg_irq_pending), .ipl_n(ipl_n)
	);

	// =====================================================================
	//  latch, EEPROM
	// =====================================================================
	rampart_latch u_latch (
		.clk(clk), .reset(cpu_reset), .wr(c_wr & c_paralel), .d(c_wd), .q(latch)
	);

	logic [7:0] ee_dout;
	/* verilator lint_off UNUSEDSIGNAL */
	logic       ee_unlocked;
	/* verilator lint_on UNUSEDSIGNAL */

	rampart_eeprom #(.T_WR(EE_T_WR)) u_eeprom (
		.clk(clk), .init_reset(init_reset), .reset(cpu_reset),
		.unlock(c_wr & c_unlock), .cpu_we(c_wr & c_eeprom & c_lds),
		.cpu_addr(c_wr ? c_a[11:1] : a[11:1]), .cpu_wdata(c_wd[7:0]),
		.cpu_rdata(ee_dout), .unlocked(ee_unlocked),
		.write_accepted(nv_write_accepted),
		.load_we(nv_load_we), .load_addr(nv_load_addr), .load_data(nv_load_data),
		.seed_we(nv_seed_we), .load_end(nv_load_end),
		.dump_addr(nv_dump_addr), .dump_data(nv_dump_data)
	);

	// =====================================================================
	//  switches and LETAs
	// =====================================================================
	logic [15:0] sw_dout;
	rampart_inputs #(.OPEN_VALUE(1'b1)) u_inputs (
		.a1(a[1]), .vblank(vblank),
		.firer_n(firer_n), .rotr_n(rotr_n), .firec_n(firec_n), .rotc_n(rotc_n),
		.firel_n(firel_n), .rotl_n(rotl_n), .coinl_n(coinl_n), .coinr_n(coinr_n),
		.service_n(service_n), .selftest_n(selftest_n), .strap(strap), .dout(sw_dout)
	);

	logic [7:0] leta_hi, leta_lo;
	rampart_leta u_leta_13a (
		.clk(clk), .ck(ce_3m58), .test(latch[13]), .resol(latch[10]), .ad(a[2:1]),
		.clks(leta_hi_clk), .dirs(leta_hi_dir), .dout(leta_hi)
	);
	rampart_leta u_leta_12a (
		.clk(clk), .ck(ce_3m58), .test(latch[11]), .resol(latch[10]), .ad(a[2:1]),
		.clks(leta_lo_clk), .dirs(leta_lo_dir), .dout(leta_lo)
	);

	// =====================================================================
	//  read data
	// =====================================================================
	localparam logic [7:0] OPEN8 = OPEN_BUS ? 8'hFF : 8'h00;

	always_comb begin
		rdata = {OPEN8, OPEN8};
		if (rom_sel)            rdata = rom_data;
		else if (!bmsel_n)      rdata = bm_dout;
		else if (!mosel_n)      rdata = mo_dout;
		else if (!cram_n)       rdata = {cram_dout, OPEN8};
		else if (!paralel_n)    rdata = sw_dout;
		else if (!leta_n)       rdata = {leta_hi, leta_lo};
		else if (!eeprom_n)     rdata = {OPEN8, ee_dout};
		else if (!adpcm_n)      rdata = {oki_dout, OPEN8};
	end

	// =====================================================================
	//  outputs
	// =====================================================================
	assign vid_a     = a[16:1];
	assign vid_din   = wdata;
	assign vid_as    = as;
	assign vid_rw    = rw;
	assign vid_uds_n = uds_n;
	assign vid_lds_n = lds_n;

	assign snd_a1   = a[1];
	assign snd_din  = wdata[15:8];
	assign oki_wr   = c_wr & c_adpcm & c_uds;
	assign oki_rd   = cyc_end & c_rw & c_adpcm;
	assign ym_wr    = c_wr & c_yamaha;
	assign ym_wr_a1 = c_a[1];
	assign ym_wr_d  = c_wd[15:8];

	assign dbg_a     = a;
	assign dbg_as    = as;
	assign dbg_rw    = rw;
	assign dbg_uds_n = uds_n;
	assign dbg_lds_n = lds_n;
	assign dbg_fc    = fc;
	assign dbg_rdata = rdata;
	assign dbg_wdata = wdata;
	assign dbg_bank  = bank;

endmodule
