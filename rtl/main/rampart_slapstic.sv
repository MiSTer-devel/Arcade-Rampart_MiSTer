`timescale 1ns/1ps
//============================================================================
//  Atari SLAPSTIC 137412-118, location 12D.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  Structure from the Xybots MiSTer core's xybots_slapstic.sv (GPL-3.0).
//  The state machine follows MAME's slapstic.cpp (BSD-3-Clause), class
//  111-118, used here as the functional reference.
//
//  The slapstic watches the CPU address bus and drives two bank-select
//  outputs.  On Rampart, BS1:BS0 replace ROM A14:A13 in the 0x100000-0x1FFFFF
//  ROM region, so the four 8 KB pages at ROM 0x40000 appear at 0x140000.
//
//  Pins as wired on this board:
//
//      /CS      = A18 & /A19 & A20 & /A21 (from the 12C GAL): 0x140000-
//                 0x17FFFF and its mirrors.  No /AS, no R/W: reads and
//                 writes both count.
//      CLK      = one edge per 68000 bus cycle, at any address.  /CS is a
//                 data input, not a gate.
//      A13..A0  = CPU A14..A1.
//      BS1:BS0  -> 12C, which substitutes them for ROM A14:A13.
//      There is no reset pin.  The chip powers up in bank BANKSTART.
//
//  Address tests (all values are chip addresses, a = CPU A14..A1):
//
//      in(m, v)   = /CS low  and (a & m) == v
//      any(m, v)  =              (a & m) == v    (window ignored)
//      exact(v)   = /CS low  and a == v
//
//  "reset" is exact(0).  alt1 and alt3 use any(); every other test uses
//  in() or exact().  Each bus cycle is tested once per state, in the order
//  written below, and the first match wins.
//
//  Additive banking loads the current bank, adds 1 or 2 for each +1 / +2
//  access, and ends through the same commit state as alternate banking.
//  An address that matches both the +1 and +2 masks adds 1 only.
//============================================================================

module rampart_slapstic #(
	// Chip 137412-118.  Values are chip addresses (CPU A14..A1).
	parameter logic [1:0]  BANKSTART = 2'd0,
	parameter logic [13:0] BANK0     = 14'h0014,
	parameter logic [13:0] BANK1     = 14'h0034,
	parameter logic [13:0] BANK2     = 14'h0054,
	parameter logic [13:0] BANK3     = 14'h0074,
	parameter logic [13:0] ALT1_M    = 14'h007F,
	parameter logic [13:0] ALT1_V    = 14'h0002,
	parameter logic [13:0] ALT2_M    = 14'h3FFF,
	parameter logic [13:0] ALT2_V    = 14'h1950,
	parameter logic [13:0] ALT3_M    = 14'h0067,
	parameter logic [13:0] ALT3_V    = 14'h0020,
	parameter logic [13:0] ALT4_M    = 14'h3F9F,
	parameter logic [13:0] ALT4_V    = 14'h0014,
	parameter int          ALTSHIFT  = 3,
	parameter logic [13:0] ADD1_M    = 14'h3FFF,
	parameter logic [13:0] ADD1_V    = 14'h1958,
	parameter logic [13:0] ADD2_M    = 14'h3FFF,
	parameter logic [13:0] ADD2_V    = 14'h1959,
	parameter logic [13:0] ADDP1_M   = 14'h3F73,
	parameter logic [13:0] ADDP1_V   = 14'h3052,
	parameter logic [13:0] ADDP2_M   = 14'h3F67,
	parameter logic [13:0] ADDP2_V   = 14'h3042,
	parameter logic [13:0] ADD3_M    = 14'h3FF8,
	parameter logic [13:0] ADD3_V    = 14'h30E0,

	// The chip has no reset pin, so a board reset (watchdog, reset jumper or
	// OSD reset) leaves the bank and state alone.  Set to 1 to reset them on every
	// board reset instead, as MAME does.
	parameter bit          SLAP_RESET_ON_BOARD_RESET = 1'b0
) (
	input  logic        clk,          // clk_sys
	input  logic        power_on,     // active high: power-up state, bank BANKSTART
	input  logic        board_reset,  // active high: ignored unless the parameter is set

	// One pulse per 68000 bus cycle (one CLK edge), for EVERY cycle: reads,
	// writes, opcode fetches and interrupt acknowledges, inside the window
	// or not.  Pulse it after the cycle's ROM address has been formed: the
	// new bank takes effect from the next cycle.
	input  logic        cyc,
	input  logic        cs_n,         // /CS, active low
	input  logic [14:1] a,            // CPU A14..A1 = chip A13..A0

	output logic [1:0]  bank,         // {BS1, BS0}

	// Current state in MAME's numbering (0 idle ... 9 additive set).
	// Diagnostic only.
	output logic [3:0]  dbg_state
);

	localparam logic [3:0] ST_IDLE       = 4'd0;
	localparam logic [3:0] ST_ACTIVE     = 4'd1;
	localparam logic [3:0] ST_ALT_VALID  = 4'd2;
	localparam logic [3:0] ST_ALT_SELECT = 4'd3;
	localparam logic [3:0] ST_ALT_COMMIT = 4'd4;
	localparam logic [3:0] ST_ADD_LOAD   = 4'd8;
	localparam logic [3:0] ST_ADD_SET    = 4'd9;

	logic [3:0] state;
	logic [1:0] loaded_bank;

	logic [13:0] ca;
	assign ca = a;

	logic in_win;
	assign in_win = ~cs_n;

	function automatic logic m_in(input logic [13:0] mask, input logic [13:0] val);
		m_in = in_win && ((ca & mask) == val);
	endfunction

	function automatic logic m_any(input logic [13:0] mask, input logic [13:0] val);
		m_any = ((ca & mask) == val);
	endfunction

	function automatic logic m_exact(input logic [13:0] val);
		m_exact = in_win && (ca == val);
	endfunction

	logic hit_reset, hit_b0, hit_b1, hit_b2, hit_b3;
	logic hit_alt1, hit_alt2, hit_alt3, hit_alt4;
	logic hit_add1, hit_add2, hit_addp1, hit_addp2, hit_add3;

	always_comb begin
		hit_reset = m_exact(14'h0000);
		hit_b0    = m_exact(BANK0);
		hit_b1    = m_exact(BANK1);
		hit_b2    = m_exact(BANK2);
		hit_b3    = m_exact(BANK3);
		hit_alt1  = m_any(ALT1_M, ALT1_V);
		hit_alt2  = m_in (ALT2_M, ALT2_V);
		hit_alt3  = m_any(ALT3_M, ALT3_V);
		hit_alt4  = m_in (ALT4_M, ALT4_V);
		hit_add1  = m_in (ADD1_M, ADD1_V);
		hit_add2  = m_in (ADD2_M, ADD2_V);
		hit_addp1 = m_in (ADDP1_M, ADDP1_V);
		hit_addp2 = m_in (ADDP2_M, ADDP2_V);
		hit_add3  = m_in (ADD3_M, ADD3_V);
	end

	// The alternate bank comes from two address bits of the third access.
	logic [1:0] alt_pick;
	assign alt_pick = ca[ALTSHIFT+1 -: 2];

	always_ff @(posedge clk) begin
		if (power_on || (SLAP_RESET_ON_BOARD_RESET && board_reset)) begin
			state       <= ST_IDLE;
			bank        <= BANKSTART;
			loaded_bank <= 2'd0;
		end else if (cyc) begin
			case (state)

			// Waits for an access to the window base.
			ST_IDLE:
				if (hit_reset) state <= ST_ACTIVE;

			// Direct switch, or the start of an alternate or additive
			// sequence.  Anything else is ignored.
			ST_ACTIVE:
				if (hit_b0)        begin bank <= 2'd0; state <= ST_IDLE; end
				else if (hit_b1)   begin bank <= 2'd1; state <= ST_IDLE; end
				else if (hit_b2)   begin bank <= 2'd2; state <= ST_IDLE; end
				else if (hit_b3)   begin bank <= 2'd3; state <= ST_IDLE; end
				else if (hit_alt1) state <= ST_ALT_VALID;
				else if (hit_add1) state <= ST_ADD_LOAD;

			// The next cycle must be alt2, or the additive start.  Anything
			// else breaks the sequence.
			ST_ALT_VALID:
				if (hit_reset)     state <= ST_ACTIVE;
				else if (hit_alt2) state <= ST_ALT_SELECT;
				else if (hit_add1) state <= ST_ADD_LOAD;
				else               state <= ST_ACTIVE;

			// The next cycle, at any address, picks the bank.
			ST_ALT_SELECT:
				if (hit_reset)     state <= ST_ACTIVE;
				else if (hit_alt3) begin
					loaded_bank <= alt_pick;
					state       <= ST_ALT_COMMIT;
				end else           state <= ST_ACTIVE;

			// Waits for a commit access; other cycles are ignored.
			ST_ALT_COMMIT:
				if (hit_reset)     state <= ST_ACTIVE;
				else if (hit_alt4) begin
					bank  <= loaded_bank;
					state <= ST_IDLE;
				end

			// The next cycle must be the additive load.
			ST_ADD_LOAD:
				if (hit_reset)     state <= ST_ACTIVE;
				else if (hit_add2) begin
					loaded_bank <= bank;
					state       <= ST_ADD_SET;
				end else           state <= ST_ACTIVE;

			// Adds to the loaded bank until the end access, then commits
			// through ST_ALT_COMMIT.  Other cycles are ignored.
			ST_ADD_SET:
				if (hit_reset)      state <= ST_ACTIVE;
				else if (hit_addp1) loaded_bank <= loaded_bank + 2'd1;
				else if (hit_addp2) loaded_bank <= loaded_bank + 2'd2;
				else if (hit_add3)  state <= ST_ALT_COMMIT;

			default: state <= ST_IDLE;
			endcase
		end
	end

	assign dbg_state = state;

endmodule
