`timescale 1ns/1ps
//============================================================================
//  Rampart motion-object processor: the MOB 137593-001 at 2K/L.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  Adapted from skullxbo_mob.sv of the Skull & Crossbones MiSTer core
//  (GPL-3.0; the per-line walk started by the line strobe, the word-select
//  fetch and the named timing parameters) and from klax_motion_objects.v of
//  the Klax MiSTer core (GPL-2.0-or-later; the 9-bit vertical test, the tile
//  order and the packed 8x8x4 row fetch).
//
//  Once per line, on the line strobe, the MOB renders one future line into
//  the line buffer bank that is not being displayed:
//
//    1. read SLIP[band], band = line / 8 (32 words at MO RAM 0x3F40)
//    2. for each entry of the linked list (4 words at 8 x LINK):
//         w3  Y[15:7], WIDTH-1[6:4], HEIGHT-1[2:0]
//         w0  LINK[9:0] of the next entry
//         d = (line + Y + 8 x HEIGHT) mod 512; the object covers the line
//         when d < 8 x HEIGHT, at tile row d/8 and pixel row d mod 8
//         on a hit:
//         w1  HFLIP[15], CODE[14:0]
//         w2  X[15:7], COLOUR[3:0]
//         then WIDTH tiles of 8 pixels are written at X, X+1, ...
//    3. the walk ends on an entry that links to itself (or after 1024)
//
//  Tile t of tile row r is CODE + r x WIDTH + t, wrapped to the 4096 tiles
//  of the 128 KB ROM.  HFLIP mirrors each tile and takes the tiles from the
//  right.  ROM byte = tile x 32 + pixel row x 4 + x / 2, even pixel in the
//  high nibble.  The ROM holds the complement of the pen: nibble F is
//  transparent (not written) and pen = NOT nibble.
//
//  STEP_CE14 = 1 paces RAM reads and pixel writes at 14 MHz (one per
//  ce_14m), which keeps the busiest measured line well inside the line
//  period; 0 runs them at clk_sys.  late pulses when a line strobe arrives
//  before the walk has finished (the walk then restarts for the new line).
//============================================================================

module rampart_mob #(
	parameter bit STEP_CE14 = 1'b1
)(
	input  logic        clk,
	input  logic        reset,
	input  logic        ce_14m,

	input  logic        start,       // line strobe
	input  logic  [8:0] line,        // the line to render

	// MO RAM (through 8M)
	output logic  [1:0] vas,
	output logic  [9:4] link_hi,
	output logic  [6:1] va_lo,
	input  logic [15:0] ram_q,

	// graphics ROM
	output logic [16:0] rom_a,
	input  logic  [7:0] rom_q,

	// line buffer write
	output logic        lb_we,
	output logic  [8:0] lb_wa,
	output logic  [7:0] lb_wd,       // {COLOUR, pen}

	output logic        busy,
	output logic        late
);

	typedef enum logic [2:0] {
		S_IDLE, S_SLIP, S_W3, S_W0, S_W1, S_W2, S_PIX, S_NEXT
	} state_t;

	state_t      st;
	logic  [1:0] rd_ph;          // 0 = address, 1 = wait, 2 = data
	logic  [8:0] tline;
	logic  [9:0] link, nxt;
	logic [10:0] cnt;
	logic  [8:0] ypos;
	logic  [2:0] wm1, hm1;
	logic        hflip;
	logic [11:0] code;
	logic  [8:0] xpos;
	logic  [3:0] colour;
	logic  [2:0] prow;
	logic [11:0] rbase;          // CODE + tile row x WIDTH
	logic  [2:0] col, px;

	wire step = STEP_CE14 ? ce_14m : 1'b1;

	// vertical test
	wire [3:0] htiles = {1'b0, hm1} + 4'd1;
	wire [3:0] wtiles = {1'b0, wm1} + 4'd1;
	wire [8:0] dsum  = tline + ypos + {2'd0, htiles, 3'd0};
	wire       hit   = (dsum < {2'd0, htiles, 3'd0});

	// pixel address
	wire [2:0] tx    = hflip ? (wm1 - col) : col;
	wire [2:0] gx    = hflip ? (3'd7 - px) : px;
	wire [11:0] tcode = rbase + {9'd0, tx};
	wire [8:0] lbx   = xpos + {3'd0, col, px};

	// two-stage pixel pipeline behind the ROM read
	logic        p1_v, p2_v;
	logic  [8:0] p1_a, p2_a;
	logic        p1_s, p2_s;
	logic  [3:0] p1_c, p2_c;

	wire  [3:0] nib = p2_s ? rom_q[3:0] : rom_q[7:4];

	always_ff @(posedge clk) begin
		p2_v <= p1_v; p2_a <= p1_a; p2_s <= p1_s; p2_c <= p1_c;
		p1_v <= 1'b0;
		lb_we <= p2_v && (nib != 4'hF);
		lb_wa <= p2_a;
		lb_wd <= {p2_c, ~nib};
		late  <= 1'b0;

		if (reset) begin
			st    <= S_IDLE;
			rd_ph <= 2'd0;
			p1_v  <= 1'b0;
			p2_v  <= 1'b0;
			lb_we <= 1'b0;
		end else if (start) begin
			late  <= (st != S_IDLE);
			tline <= line;
			cnt   <= 11'd0;
			rd_ph <= 2'd0;
			st    <= S_SLIP;
		end else begin
			case (st)
				S_IDLE: ;

				S_SLIP, S_W3, S_W0, S_W1, S_W2: begin
					case (rd_ph)
						2'd0: if (step) begin
							if (st == S_SLIP) begin
								vas   <= 2'b11;
								va_lo <= {1'b1, tline[7:3]};
							end else begin
								vas     <= 2'b01;
								link_hi <= link[9:4];
								case (st)
									S_W3:    va_lo <= {link[3:0], 2'd3};
									S_W0:    va_lo <= {link[3:0], 2'd0};
									S_W1:    va_lo <= {link[3:0], 2'd1};
									default: va_lo <= {link[3:0], 2'd2};
								endcase
							end
							rd_ph <= 2'd1;
						end
						2'd1: rd_ph <= 2'd2;
						default: begin
							rd_ph <= 2'd0;
							case (st)
								S_SLIP: begin
									link <= ram_q[9:0];
									st   <= S_W3;
								end
								S_W3: begin
									ypos <= ram_q[15:7];
									wm1  <= ram_q[6:4];
									hm1  <= ram_q[2:0];
									st   <= S_W0;
								end
								S_W0: begin
									nxt <= ram_q[9:0];
									st  <= hit ? S_W1 : S_NEXT;
									prow <= dsum[2:0];
									rbase <= {9'd0, dsum[5:3]} * {8'd0, wtiles};
								end
								S_W1: begin
									hflip <= ram_q[15];
									code  <= ram_q[11:0];
									st    <= S_W2;
								end
								default: begin
									xpos   <= ram_q[15:7];
									colour <= ram_q[3:0];
									rbase  <= rbase + code;
									col    <= 3'd0;
									px     <= 3'd0;
									st     <= S_PIX;
								end
							endcase
						end
					endcase
				end

				S_PIX: if (step) begin
					rom_a <= {tcode, prow, gx[2:1]};
					p1_v  <= 1'b1;
					p1_a  <= lbx;
					p1_s  <= gx[0];
					p1_c  <= colour;
					px    <= px + 3'd1;
					if (px == 3'd7) begin
						col <= col + 3'd1;
						if (col == wm1) st <= S_NEXT;
					end
				end

				default: begin  // S_NEXT
					if (nxt == link || cnt == 11'd1023) begin
						st <= S_IDLE;
					end else begin
						link <= nxt;
						cnt  <= cnt + 11'd1;
						st   <= S_W3;
					end
				end
			endcase
		end
	end

	assign busy = (st != S_IDLE);

	/* verilator lint_off UNUSEDSIGNAL */
	wire unused_q = &{1'b0, ram_q[14:12], tline[8]};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
