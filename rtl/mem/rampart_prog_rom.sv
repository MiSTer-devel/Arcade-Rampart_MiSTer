`timescale 1ns/1ps
//============================================================================
//  Program ROM and ADPCM reads from SDRAM.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  The program ROM sockets live in SDRAM, one 1 MB region per memory-decoder
//  output Y0..Y3 (word base = Y x 0x80000).  A ROM read is one single-word
//  SDRAM read, issued the clock after /AS asserts.  The controller answers
//  in about ten clk_sys, inside the 12 clk_sys between /AS and the point
//  where the 68000 samples /DTACK, so the CPU sees no wait states.  To keep
//  that true, refresh and the second client (the MSM6295 ADPCM reads) may
//  only start inside `start_ok`, a window the bus logic opens when the
//  current CPU cycle no longer needs the SDRAM and the next ROM read cannot
//  arrive before the operation ends.
//
//  Chip address width: each socket pair ignores the address lines its chips
//  do not have.  64K x 8 parts see A16..A1, 128K x 8 parts A17..A1 and
//  512K x 8 parts A19..A1.
//      variant 0 (1006): Y0 64K,  Y1 512K
//      variant 1 (1056): Y0 128K, Y1 512K
//      variant 2 (1005): Y0..Y3 128K
//============================================================================

module rampart_prog_rom #(
	parameter int AW = 24
) (
	input  logic          clk,
	input  logic          reset,

	input  logic  [1:0]   variant,

	// ---- 68000 ----
	input  logic          cpu_req,     // 1-clk pulse: a ROM read cycle started
	input  logic  [1:0]   pair,
	input  logic [19:1]   rom_a,
	output logic [15:0]   cpu_data,
	output logic          cpu_ready,   // cpu_data belongs to the current cycle

	input  logic          start_ok,    // window for refresh and the second client

	// ---- second client (ADPCM), level request held until snd_valid ----
	input  logic          snd_req,
	input  logic [AW-1:0] snd_addr,    // word address
	output logic [15:0]   snd_data,
	output logic          snd_valid,

	// ---- SDRAM controller host port ----
	output logic          sd_req,
	output logic [AW-1:0] sd_addr,
	output logic  [2:0]   sd_blen,
	input  logic          sd_ready,
	input  logic          sd_valid,
	input  logic [15:0]   sd_rdata,
	output logic          rfsh_ok
);

	// ---- ROM word address inside SDRAM -----------------------------------
	logic [18:0] mask;
	always_comb begin
		case (variant)
			2'd0:    mask = (pair == 2'd0) ? 19'h0FFFF : 19'h7FFFF;
			2'd1:    mask = (pair == 2'd0) ? 19'h1FFFF : 19'h7FFFF;
			default: mask = 19'h1FFFF;
		endcase
	end
	wire [AW-1:0] rom_word = AW'({pair, rom_a & mask});

	// ---- request tracking --------------------------------------------------
	logic          cpu_pend;
	logic [AW-1:0] cpu_addr_l;
	logic          busy_cpu, busy_snd;      // a read is in flight for ...

	wire cpu_want = cpu_req | cpu_pend;
	wire [AW-1:0] cpu_a = cpu_req ? rom_word : cpu_addr_l;
	wire go_cpu = cpu_want & sd_ready & ~busy_cpu & ~busy_snd;
	wire go_snd = ~cpu_want & snd_req & start_ok & sd_ready & ~busy_cpu & ~busy_snd;

	assign sd_req  = go_cpu | go_snd;
	assign sd_addr = go_cpu ? cpu_a : snd_addr;
	assign sd_blen = 3'd0;
	// A waiting ADPCM read goes before a refresh (the refresh waits for the
	// next window; the MSM6295 reads at most ten bytes per sample period).
	assign rfsh_ok = start_ok & ~cpu_want & ~snd_req & ~busy_cpu & ~busy_snd;

	always_ff @(posedge clk) begin
		snd_valid <= 1'b0;
		if (reset) begin
			cpu_pend <= 1'b0; busy_cpu <= 1'b0; busy_snd <= 1'b0; cpu_ready <= 1'b0;
		end else begin
			if (cpu_req) begin
				cpu_ready  <= 1'b0;
				cpu_addr_l <= rom_word;
			end
			if (go_cpu)                   cpu_pend <= 1'b0;
			else if (cpu_req)             cpu_pend <= 1'b1;

			if (go_cpu) busy_cpu <= 1'b1;
			if (go_snd) busy_snd <= 1'b1;
			if (sd_valid) begin
				if (busy_cpu) begin
					busy_cpu  <= 1'b0;
					cpu_data  <= sd_rdata;
					cpu_ready <= ~cpu_req;
				end else if (busy_snd) begin
					busy_snd  <= 1'b0;
					snd_data  <= sd_rdata;
					snd_valid <= 1'b1;
				end
			end
		end
	end

endmodule
