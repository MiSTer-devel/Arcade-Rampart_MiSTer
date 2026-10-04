`timescale 1ns/1ps
//============================================================================
//  EEPROM at 13F (2K x 8, 2816 class) and its write-unlock flop.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  Adapted from core/rtl/main/batman_eeprom_28c16.sv of the Batman MiSTer
//  core (GPL-3.0).
//
//  The part sits on D7-0 at 0x500000-0x500FFF; the cell is A11..A1.  A write
//  to 0x5A6000 sets the unlock flop, and only while it is set does a write
//  reach the EEPROM; the write then relocks it (one unlock per byte, which is
//  how the game writes).  Board /RESET clears the flop, never the contents.
//  T_WR clk_sys cycles after an accepted write the part is busy and ignores
//  further writes (0 = no busy time; the game waits a frame per byte).
//
//  MiSTer load/save (through rampart_nvram_io): load_we writes a byte from
//  either the ROM stream's factory image (seed_we) or a saved .nvm file.
//  The factory image is also kept aside, and an all-zero .nvm file (a blank
//  save slot) is replaced by it when its download ends.
//============================================================================

module rampart_eeprom #(
	parameter int T_WR = 0
) (
	input  logic        clk,
	input  logic        init_reset,
	input  logic        reset,          // board reset

	input  logic        unlock,         // 1-clk pulse: end of a write to /UNLOCK
	input  logic        cpu_we,         // 1-clk pulse: end of a low-byte write to /EEPROM
	input  logic [10:0] cpu_addr,
	input  logic  [7:0] cpu_wdata,
	output logic  [7:0] cpu_rdata,
	output logic        unlocked,
	output logic        write_accepted,

	input  logic        load_we,
	input  logic [10:0] load_addr,
	input  logic  [7:0] load_data,
	input  logic        seed_we,
	input  logic        load_end,
	input  logic [10:0] dump_addr,
	output logic  [7:0] dump_data
);

	logic [7:0] mem      [0:2047];
	logic [7:0] seed_mem [0:2047];

	// ---- busy time after a write ------------------------------------------
	localparam int BW = (T_WR < 2) ? 1 : $clog2(T_WR + 1);
	logic [BW-1:0] busy_ctr;
	wire busy = (T_WR > 0) && (busy_ctr != '0);

	assign write_accepted = cpu_we & unlocked & ~busy;

	always_ff @(posedge clk) begin
		if (init_reset || reset) unlocked <= 1'b0;
		else if (cpu_we)         unlocked <= 1'b0;
		else if (unlock)         unlocked <= 1'b1;

		if (init_reset)          busy_ctr <= '0;
		else if (write_accepted) busy_ctr <= BW'(T_WR);
		else if (busy)           busy_ctr <= busy_ctr - 1'b1;
	end

	// ---- replay of the factory image over an all-zero save file -----------
	logic        l2_seen, l2_nonzero;
	logic        rp_run, rp_run_d;
	logic [10:0] rp_addr, rp_addr_d;
	logic  [7:0] seed_q;

	always_ff @(posedge clk) begin
		if (init_reset || load_end) begin
			l2_seen <= 1'b0; l2_nonzero <= 1'b0;
		end else if (load_we && !seed_we) begin
			l2_seen <= 1'b1;
			if (load_data != 8'h00) l2_nonzero <= 1'b1;
		end

		if (init_reset) begin
			rp_run <= 1'b0; rp_addr <= '0;
		end else if (load_end && l2_seen && !l2_nonzero) begin
			rp_run <= 1'b1; rp_addr <= '0;
		end else if (rp_run) begin
			rp_addr <= rp_addr + 1'b1;
			if (&rp_addr) rp_run <= 1'b0;
		end

		if (seed_we) seed_mem[load_addr] <= load_data;
		seed_q    <= seed_mem[rp_addr];
		rp_run_d  <= rp_run;
		rp_addr_d <= rp_addr;
	end

	// ---- the array: one write port, two read ports ------------------------
	wire        we_rp  = rp_run_d & ~load_we;
	wire        we_cpu = write_accepted & ~load_we & ~we_rp;
	wire        mem_we = load_we | we_rp | we_cpu;
	wire [10:0] mem_wa = load_we ? load_addr : we_rp ? rp_addr_d : cpu_addr;
	wire  [7:0] mem_wd = load_we ? load_data : we_rp ? seed_q : cpu_wdata;

	always_ff @(posedge clk) begin
		if (mem_we) mem[mem_wa] <= mem_wd;
		cpu_rdata <= mem[cpu_addr];
		dump_data <= mem[dump_addr];
	end

endmodule
