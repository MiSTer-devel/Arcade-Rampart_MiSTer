`timescale 1ns/1ps
//============================================================================
//  Rampart main CPU: fx68k (cycle-exact 68000) at 7.159 MHz.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  Adapted from core/rtl/main/skullxbo_cpu.sv of the Skull & Crossbones
//  MiSTer core (GPL-3.0).  The CPU is Jorge Cwik's fx68k (GPL-3.0-or-later),
//  vendored unchanged in rtl/lib/fx68k.
//
//  Clock: the 68000 runs from clk_sys with two enables 4 clk_sys apart:
//      enPhi1 = ce_7m          (CPU clock rising; also the pixel-count edge)
//      enPhi2 = ce_7m + 4      (CPU clock falling)
//  so one CPU clock is exactly one pixel clock.  The board's phase between
//  the CPU clock and the pixel clock is not drawn; this choice puts both on
//  the same edge.  en_phi2 is an output because the wait-state logic must
//  count the same edges on which fx68k samples /DTACK.
//
//  Deviations from a literal 68000:
//    * HALT is tied inactive (fx68k's reset input does the whole reset);
//    * pwrUp follows reset;
//    * BERR, BR and BGACK are tied inactive: the board has no bus master
//      other than the CPU and no bus-error source.
//  reset_inst is high while a RESET instruction drives the reset pin.
//============================================================================

module rampart_cpu
(
	input  logic        clk,        // clk_sys, 57.272727 MHz
	input  logic        ce_7m,      // clk_sys / 8
	input  logic        reset,      // active high: board /RESET

	input  logic  [2:0] ipl_n,      // {/IPL2,/IPL1,/IPL0}, 111 = none

	output logic [23:1] a,
	output logic [15:0] wdata,
	input  logic [15:0] rdata,
	output logic        as,         // 1 while /AS is asserted
	output logic        uds_n,
	output logic        lds_n,
	output logic        rw,         // 1 = read, 0 = write
	input  logic        dtack,      // 1 = /DTACK asserted
	input  logic        vpa_n,
	output logic  [2:0] fc,
	output logic        reset_inst,

	output logic        en_phi1,    // the enable that clocks each CPU clock rising
	output logic        en_phi2     // the enable that clocks each CPU clock falling
);

	// ce_7m loads 1, so pcnt is 0 in the ce_7m cycle and 4 half-way through.
	logic [2:0] pcnt;
	always_ff @(posedge clk) begin
		if (ce_7m) pcnt <= 3'd1;
		else       pcnt <= pcnt + 3'd1;
	end

	assign en_phi1 = ce_7m;
	assign en_phi2 = (pcnt == 3'd4);

	// Two-stage IPL staging.  fx68k synchronises IPL again under enPhi2, so
	// this adds a fixed, sub-CPU-clock delay only.
	logic [2:0] ipl_r, ipl_rr;
	always_ff @(posedge clk) begin
		if (reset) begin
			ipl_r  <= 3'b111;
			ipl_rr <= 3'b111;
		end else begin
			ipl_r  <= ipl_n;
			ipl_rr <= ipl_r;
		end
	end

	wire fx_as_n, fx_reset_n;

	/* verilator lint_off UNUSEDSIGNAL */
	wire fx_e, fx_vma_n, fx_bg_n, fx_halted_n;
	/* verilator lint_on UNUSEDSIGNAL */

	assign as         = ~fx_as_n;
	assign reset_inst = ~fx_reset_n;

	fx68k u_fx68k (
		.clk      (clk),
		.HALTn    (1'b1),
		.extReset (reset),
		.pwrUp    (reset),
		.enPhi1   (en_phi1),
		.enPhi2   (en_phi2),

		.eRWn     (rw),
		.ASn      (fx_as_n),
		.LDSn     (lds_n),
		.UDSn     (uds_n),
		.E        (fx_e),
		.VMAn     (fx_vma_n),

		.FC0      (fc[0]),
		.FC1      (fc[1]),
		.FC2      (fc[2]),
		.BGn      (fx_bg_n),
		.oRESETn  (fx_reset_n),
		.oHALTEDn (fx_halted_n),

		.DTACKn   (~dtack),
		.VPAn     (vpa_n),
		.BERRn    (1'b1),
		.BRn      (1'b1),
		.BGACKn   (1'b1),
		.IPL0n    (ipl_rr[0]),
		.IPL1n    (ipl_rr[1]),
		.IPL2n    (ipl_rr[2]),

		.iEdb     (rdata),
		.oEdb     (wdata),
		.eab      (a)
	);

endmodule
