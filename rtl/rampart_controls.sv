`timescale 1ns/1ps
//============================================================================
//  Rampart cabinet controls from MiSTer inputs.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//  Sensitivity scaler from blstroid_whirly.sv of the Blasteroids MiSTer core
//  (GPL-3.0).
//
//  This is the cabinet wiring: it turns the MiSTer pads, mouse,
//  spinners, paddles and analog sticks into the lines the game board sees.
//
//  Pads.  joy_N is the hps_io joystick word: [0] right, [1] left, [2] down,
//  [3] up, then the CONF_STR J1 list: [4] Fire, [5] Rotate, [6] Coin,
//  [7] Start.  The joystick cabinets use 4-way sticks, so unless `joy8` is set
//  a diagonal keeps the direction already held (or the vertical one, if
//  neither was held), and the board never sees two switches closed at once.
//  Player 1 also gets Fire and Rotate from the mouse buttons.  The board has
//  two coin chutes: player 1 Coin is the left chute, player 2 Coin the right,
//  and player 3 Coin is the SERVICE input (a service credit).  The trackball
//  and the standard joystick boards have no start buttons (Fire starts a
//  game); the Japanese board wires Start for players 1 and 2.
//
//  Trackballs.  Each player's X and Y are the sum of every source, so no OSD
//  source selector is needed:
//    mouse   player 1 only, both axes (ps2_mouse, 9-bit signed deltas);
//    spinner X only (spinner_N: [7:0] signed delta, [8] toggles per update);
//    paddle  X only, the change of the absolute position; a jump of more
//            than 64 in one update (a paddle being plugged in) is ignored;
//    stick   the left analog stick, as a speed: full deflection is about
//            29 counts per frame, with a small dead zone;
//    d-pad   the same speed as a full stick, used when the stick is centred.
//  The sum is scaled by `sens` in eighths (the table below; 0 = 1x exactly,
//  with the remainder carried so slow motion is never rounded away) and paced
//  by rampart_tball_axis.
//
//  Direction.  The game negates each LETA reading, so rolling right or down
//  must count the LETA down.  `inv_x` / `inv_y` flip an axis.
//
//  While `pause` is high no new motion is taken.
//============================================================================

module rampart_controls #(
	parameter int unsigned SMOOTH_K   = 458182,   // see rampart_tball_axis
	parameter int unsigned RATE_CAP   = 29,
	parameter int          TRK_STEP   = 2048,
	parameter int unsigned STICK_TICK = 4096,     // clk_sys per stick/d-pad step
	parameter int          STICK_DZ   = 12        // analog dead zone, of 127
) (
	input  logic        clk,
	input  logic        reset,
	input  logic        pause,

	input  logic [31:0] joy_0, joy_1, joy_2,
	input  logic [15:0] ana_0, ana_1, ana_2,      // [7:0] X, [15:8] Y, signed
	input  logic  [8:0] spin_0, spin_1, spin_2,
	input  logic  [7:0] pad_0, pad_1, pad_2,
	input  logic [24:0] ps2_mouse,

	input  logic  [3:0] sens,                     // OSD index, 0 = 1x
	input  logic        inv_x,
	input  logic        inv_y,
	input  logic        joy8,                     // 1 = pass diagonals

	output logic  [3:0] p1_joy, p2_joy, p3_joy,   // {up, down, left, right}
	output logic  [2:0] p1_btn, p2_btn, p3_btn,   // {start, rotate, fire}
	output logic        coin1,
	output logic        coin2,
	output logic        service,
	output logic  [5:0] tb_clk,                   // P1 X, P1 Y, P2 X, P2 Y, P3 X, P3 Y
	output logic  [5:0] tb_dir
);

	// =====================================================================
	//  buttons and 4-way sticks
	// =====================================================================
	wire [3:0] raw1 = {joy_0[3], joy_0[2], joy_0[1], joy_0[0]};
	wire [3:0] raw2 = {joy_1[3], joy_1[2], joy_1[1], joy_1[0]};
	wire [3:0] raw3 = {joy_2[3], joy_2[2], joy_2[1], joy_2[0]};

	function automatic logic [3:0] four_way(input logic [3:0] held, input logic [3:0] now);
		if ((now & (now - 4'd1)) == 4'd0) four_way = now;              // 0 or 1 switch
		else if ((held & now) != 4'd0)    four_way = held & now & ~((held & now) - 4'd1);
		else if (now[3])                  four_way = 4'b1000;         // up
		else if (now[2])                  four_way = 4'b0100;         // down
		else if (now[1])                  four_way = 4'b0010;         // left
		else                              four_way = 4'b0001;
	endfunction

	logic [3:0] f1, f2, f3;
	always_ff @(posedge clk) begin
		if (reset) begin
			f1 <= 4'd0; f2 <= 4'd0; f3 <= 4'd0;
		end else begin
			f1 <= four_way(f1, raw1);
			f2 <= four_way(f2, raw2);
			f3 <= four_way(f3, raw3);
		end
	end
	assign p1_joy = joy8 ? raw1 : f1;
	assign p2_joy = joy8 ? raw2 : f2;
	assign p3_joy = joy8 ? raw3 : f3;

	assign p1_btn  = {joy_0[7], joy_0[5] | ps2_mouse[1], joy_0[4] | ps2_mouse[0]};
	assign p2_btn  = {joy_1[7], joy_1[5], joy_1[4]};
	assign p3_btn  = {joy_2[7], joy_2[5], joy_2[4]};
	assign coin1   = joy_0[6];
	assign coin2   = joy_1[6];
	assign service = joy_2[6];

	// =====================================================================
	//  trackball motion sources (screen direction: right and down positive)
	// =====================================================================
	// ---- mouse, player 1 ----
	logic ms_t;
	always_ff @(posedge clk) ms_t <= ps2_mouse[24];
	wire        ms_new = (ps2_mouse[24] != ms_t);
	wire signed [10:0] ms_x = ms_new ?  11'($signed({ps2_mouse[4], ps2_mouse[15:8]}))  : 11'sd0;
	wire signed [10:0] ms_y = ms_new ? 11'sd0 - 11'($signed({ps2_mouse[5], ps2_mouse[23:16]})) : 11'sd0;  // PS/2 Y is up

	// ---- spinners ----
	logic [2:0] sp_t;
	always_ff @(posedge clk) sp_t <= {spin_2[8], spin_1[8], spin_0[8]};
	wire signed [10:0] sp_x0 = (spin_0[8] != sp_t[0]) ? 11'($signed(spin_0[7:0])) : 11'sd0;
	wire signed [10:0] sp_x1 = (spin_1[8] != sp_t[1]) ? 11'($signed(spin_1[7:0])) : 11'sd0;
	wire signed [10:0] sp_x2 = (spin_2[8] != sp_t[2]) ? 11'($signed(spin_2[7:0])) : 11'sd0;

	// ---- paddles ----
	logic [7:0] pd_p0, pd_p1, pd_p2;
	always_ff @(posedge clk) begin pd_p0 <= pad_0; pd_p1 <= pad_1; pd_p2 <= pad_2; end
	function automatic logic signed [10:0] pad_delta(input logic [7:0] now, input logic [7:0] prev);
		logic signed [9:0] d;
		d = $signed({2'b00, now}) - $signed({2'b00, prev});
		pad_delta = (d > 10'sd64 || d < -10'sd64) ? 11'sd0 : 11'(d);
	endfunction
	wire signed [10:0] pd_x0 = pad_delta(pad_0, pd_p0);
	wire signed [10:0] pd_x1 = pad_delta(pad_1, pd_p1);
	wire signed [10:0] pd_x2 = pad_delta(pad_2, pd_p2);

	// ---- analog stick and d-pad as a speed ----
	localparam int TW = $clog2(STICK_TICK);
	logic [TW-1:0] tdiv;
	logic          tick;
	always_ff @(posedge clk) begin
		if (reset) begin tdiv <= '0; tick <= 1'b0; end
		else begin
			tick <= (tdiv == TW'(STICK_TICK - 1));
			tdiv <= (tdiv == TW'(STICK_TICK - 1)) ? '0 : tdiv + 1'b1;
		end
	end

	localparam logic signed [7:0] DZ = 8'(STICK_DZ);

	function automatic logic signed [7:0] speed(input logic [7:0] a, input logic neg, input logic pos);
		logic signed [7:0] s;
		s = $signed(a);
		if (s > DZ || s < -DZ)                     speed = (a == 8'h80) ? -8'sd127 : s;
		else if (pos)                               speed = 8'sd127;
		else if (neg)                               speed = -8'sd127;
		else                                        speed = 8'sd0;
	endfunction

	wire signed [7:0] v_x0 = speed(ana_0[7:0],  joy_0[1], joy_0[0]);
	wire signed [7:0] v_y0 = speed(ana_0[15:8], joy_0[3], joy_0[2]);
	wire signed [7:0] v_x1 = speed(ana_1[7:0],  joy_1[1], joy_1[0]);
	wire signed [7:0] v_y1 = speed(ana_1[15:8], joy_1[3], joy_1[2]);
	wire signed [7:0] v_x2 = speed(ana_2[7:0],  joy_2[1], joy_2[0]);
	wire signed [7:0] v_y2 = speed(ana_2[15:8], joy_2[3], joy_2[2]);

	// Speed integrator: one count per 1024 speed units, taken every tick, so
	// full deflection (127) gives 127 * 13 983 / 1024 = 1734 counts/s.
	logic signed [7:0]  vel  [0:5];
	logic signed [10:0] racc [0:5];
	logic signed [10:0] rate [0:5];
	logic signed [10:0] scr  [0:5];     // per-axis sum, screen direction
	always_comb begin
		vel[0] = v_x0; vel[1] = v_y0; vel[2] = v_x1;
		vel[3] = v_y1; vel[4] = v_x2; vel[5] = v_y2;
		scr[0] = ms_x + sp_x0 + pd_x0 + rate[0];
		scr[1] = ms_y + rate[1];
		scr[2] = sp_x1 + pd_x1 + rate[2];
		scr[3] = rate[3];
		scr[4] = sp_x2 + pd_x2 + rate[4];
		scr[5] = rate[5];
	end

	logic signed [11:0] rsum [0:5];     // |racc + vel| <= 1150
	always_comb for (int i = 0; i < 6; i++) rsum[i] = 12'(racc[i]) + 12'(vel[i]);

	always_ff @(posedge clk) begin
		for (int i = 0; i < 6; i++) begin
			if (reset) begin
				racc[i] <= '0; rate[i] <= '0;
			end else if (tick) begin
				if (rsum[i] >= 12'sd1024)       begin racc[i] <= 11'(rsum[i] - 12'sd1024); rate[i] <=  11'sd1; end
				else if (rsum[i] <= -12'sd1024) begin racc[i] <= 11'(rsum[i] + 12'sd1024); rate[i] <= -11'sd1; end
				else                            begin racc[i] <= 11'(rsum[i]);             rate[i] <=  11'sd0; end
			end else begin
				rate[i] <= 11'sd0;
			end
		end
	end

	// =====================================================================
	//  sensitivity, direction, pacing
	// =====================================================================
	// Multiplier in eighths.  Index order matches the OSD list: 1x first, so a
	// cleared status word is the default, then faster, then slower.
	logic [5:0] mul8;
	always_comb begin
		case (sens)
			4'd0:  mul8 = 6'd8;    // 1x
			4'd1:  mul8 = 6'd9;    // 1.125x
			4'd2:  mul8 = 6'd10;   // 1.25x
			4'd3:  mul8 = 6'd11;   // 1.375x
			4'd4:  mul8 = 6'd12;   // 1.5x
			4'd5:  mul8 = 6'd14;   // 1.75x
			4'd6:  mul8 = 6'd16;   // 2x
			4'd7:  mul8 = 6'd20;   // 2.5x
			4'd8:  mul8 = 6'd24;   // 3x
			4'd9:  mul8 = 6'd32;   // 4x
			4'd10: mul8 = 6'd2;    // 0.25x
			4'd11: mul8 = 6'd3;    // 0.375x
			4'd12: mul8 = 6'd4;    // 0.5x
			4'd13: mul8 = 6'd5;    // 0.625x
			4'd14: mul8 = 6'd6;    // 0.75x
			default: mul8 = 6'd7;  // 0.875x
		endcase
	end

	logic signed [15:0] frac [0:5];
	logic signed [15:0] q    [0:5];
	logic signed [15:0] w    [0:5];
	logic signed [10:0] c    [0:5];
	logic signed [10:0] cnt  [0:5];     // registered, LETA count direction
	always_comb begin
		for (int i = 0; i < 6; i++) begin
			// |scr| <= 1023 and mul8 <= 32, so the product fits 16 bits.
			q[i] = (16'(pause ? 11'sd0 : scr[i]) * $signed({10'd0, mul8})) + frac[i];
			w[i] = q[i] >>> 3;                       // floor: the residue is 0..7
			c[i] = (w[i] > 16'sd1023) ? 11'sd1023 : (w[i] < -16'sd1023) ? -11'sd1023 : 11'(w[i]);
		end
	end
	always_ff @(posedge clk) begin
		for (int i = 0; i < 6; i++) begin
			if (reset) begin
				frac[i] <= '0; cnt[i] <= '0;
			end else begin
				frac[i] <= q[i] - (w[i] <<< 3);
				// rolling right or down counts the LETA down
				cnt[i]  <= ((i % 2 == 1) ? inv_y : inv_x) ? c[i] : -c[i];
			end
		end
	end

	genvar g;
	generate for (g = 0; g < 6; g++) begin : g_axis
		rampart_tball_axis #(.SMOOTH_K(SMOOTH_K), .RATE_CAP(RATE_CAP), .STEP(TRK_STEP)) u_axis (
			.clk(clk), .reset(reset), .delta(cnt[g]), .q_clk(tb_clk[g]), .q_dir(tb_dir[g])
		);
	end endgenerate

	/* verilator lint_off UNUSEDSIGNAL */
	wire _unused = &{1'b0, joy_0[31:8], joy_1[31:8], joy_2[31:8], ps2_mouse[7:6], ps2_mouse[3:2], 1'b0};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
