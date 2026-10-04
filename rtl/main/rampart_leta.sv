`timescale 1ns/1ps
//============================================================================
//  Atari LETA 137304-2002: four quadrature counters (13A and 12A-1).
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  Behaviour follows the documented operation of JROK's leta_rep.vhd, a
//  freeware functional replacement for the part carried in the Atari
//  System 1 MiSTer core; none of its code is copied.  The structure follows
//  core/rtl/main/blstroid_leta.sv of the Blasteroids MiSTer core (GPL-3.0).
//
//  Each channel has a CLK and a DIR input.  On every rising edge of the chip
//  clock (CK = /1H on this board) both inputs are shifted into 3-sample
//  filters; a level counts as settled once three samples agree.  A settled
//  change of one line counts the channel up or down by one.  With RESOL
//  low only every other transition counts.
//  TEST high clears all four counters and makes the data pins show the raw
//  inputs, inverted: {CLK3,DIR3,CLK2,DIR2,CLK1,DIR1,CLK0,DIR0}, for any
//  address.  The joystick boards run both chips in TEST and read the
//  switches this way.
//  A1:A0 (CPU A2:A1) select the channel.  The part has no reset pin; the
//  counters power up at 0.
//============================================================================

module rampart_leta (
	input  logic       clk,
	input  logic       ck,          // 1-clk pulse per CK rising edge
	input  logic       test,
	input  logic       resol,
	input  logic [1:0] ad,
	input  logic [3:0] clks,
	input  logic [3:0] dirs,
	output logic [7:0] dout
);

	// four channels packed: counter i = cnt[8i+7:8i], filters ch/dh[3i+2:3i]
	/* verilator lint_off PROCASSINIT */
	logic [31:0] cnt = 32'd0;
	logic [11:0] ch = 12'd0, dh = 12'd0;
	logic  [3:0] cl = 4'd0, dl = 4'd0;       // last settled CLK / DIR
	/* verilator lint_on PROCASSINIT */

	always_ff @(posedge clk) begin
		if (ck) begin
			for (int i = 0; i < 4; i++) begin
				if (test) begin
					ch[3*i +: 3] <= 3'd0; dh[3*i +: 3] <= 3'd0; cnt[8*i +: 8] <= 8'd0;
					cl[i] <= 1'b0; dl[i] <= 1'b0;
				end else begin
					ch[3*i +: 3] <= {ch[3*i +: 2], clks[i]};
					dh[3*i +: 3] <= {dh[3*i +: 2], dirs[i]};
					if (ch[3*i +: 3] == 3'b000) cl[i] <= 1'b0; else if (ch[3*i +: 3] == 3'b111) cl[i] <= 1'b1;
					if (dh[3*i +: 3] == 3'b000) dl[i] <= 1'b0; else if (dh[3*i +: 3] == 3'b111) dl[i] <= 1'b1;
					// settled (CLK, DIR) against the previous settled pair
					case ({ch[3*i +: 3] == 3'b111, ch[3*i +: 3] == 3'b000,
					       dh[3*i +: 3] == 3'b111, dh[3*i +: 3] == 3'b000})
						4'b1001: begin  // (1,0)
							if (cl[i] && dl[i])                  cnt[8*i +: 8] <= cnt[8*i +: 8] - 8'd1;
							else if (!cl[i] && !dl[i] && resol)  cnt[8*i +: 8] <= cnt[8*i +: 8] + 8'd1;
						end
						4'b1010: begin  // (1,1)
							if (cl[i] && !dl[i])                 cnt[8*i +: 8] <= cnt[8*i +: 8] + 8'd1;
							else if (!cl[i] && dl[i] && resol)   cnt[8*i +: 8] <= cnt[8*i +: 8] - 8'd1;
						end
						4'b0110: begin  // (0,1)
							if (!cl[i] && !dl[i])                cnt[8*i +: 8] <= cnt[8*i +: 8] - 8'd1;
							else if (cl[i] && dl[i] && resol)    cnt[8*i +: 8] <= cnt[8*i +: 8] + 8'd1;
						end
						4'b0101: begin  // (0,0)
							if (!cl[i] && dl[i])                 cnt[8*i +: 8] <= cnt[8*i +: 8] + 8'd1;
							else if (cl[i] && !dl[i] && resol)   cnt[8*i +: 8] <= cnt[8*i +: 8] - 8'd1;
						end
						default: ;
					endcase
				end
			end
		end
	end

	assign dout = test ? ~{clks[3], dirs[3], clks[2], dirs[2], clks[1], dirs[1], clks[0], dirs[0]}
	                   : cnt[8*ad +: 8];

endmodule
