`timescale 1ns/1ps
//============================================================================
//  Rampart motion-object RAM (5N/6N, 2 x 8K x 8 = 16 KB) with the 8M
//  address mux and the 4L arbiter.
//
//  Copyright (C) 2026 RetroShrimp.  GPL-3.0-or-later; see LICENSE and NOTICE.md.
//
//  The CPU sees the RAM at 0x3E0000 (16 KB, mirrored); it holds the object
//  list, the SLIP table and the program's work RAM and stack.  The MOB
//  reads it through the 8M mux, which builds VA13..VA7 from VAS1:VAS0:
//
//      VAS 00   CPU A13..A7
//      VAS 01   0, LINK9..LINK4        object entry LINK
//      VAS 1x   1111110                the SLIP row, byte 0x3F00-0x3F7F
//
//  VA6..VA1 come from the MOB (LINK3..0 and the word select, or 1 and the
//  SLIP band).  Here the CPU and the MOB have separate RAM ports, so the
//  arbiter does not gate data.  WAIT_MODEL = 1 uses the 4L GAL (14 MHz)
//  for the CPU wait: its pin 18 releases a CPU access only while no
//  next-line work is pending.  The 4L input wiring is not drawn anywhere;
//  the connections below are a best guess.  WAIT_MODEL = 0 never waits.
//============================================================================

module rampart_moram #(
	parameter int WAIT_MODEL = 0
)(
	input  logic        clk,
	input  logic        ce_14m,
	input  logic        half,
	input  logic        pnxl,        // 7K pin 17
	input  logic        nxl,         // 7K pin 14
	input  logic        vsync_n,

	// CPU port
	input  logic [13:1] cpu_a,
	input  logic [15:0] cpu_din,
	output logic [15:0] cpu_dout,
	input  logic        cpu_rw,
	input  logic        cpu_as_n,
	input  logic        cpu_uds_n,
	input  logic        cpu_lds_n,
	input  logic        mosel_n,     // no /AS in this select
	output logic        cpu_wait,

	// MOB port
	input  logic  [1:0] vas,         // {VAS1, VAS0}
	input  logic  [9:4] link_hi,     // LINK9..LINK4
	input  logic  [6:1] va_lo,       // VA6..VA1
	output logic [15:0] mob_q
);

	logic [7:0] ram_hi [0:8191];
	logic [7:0] ram_lo [0:8191];

	wire cpu_cyc   = ~mosel_n & ~cpu_as_n;
	wire cpu_wr_hi = cpu_cyc & ~cpu_rw & ~cpu_uds_n;
	wire cpu_wr_lo = cpu_cyc & ~cpu_rw & ~cpu_lds_n;

	always_ff @(posedge clk) begin
		if (cpu_wr_hi) begin
			ram_hi[cpu_a]  <= cpu_din[15:8];
			cpu_dout[15:8] <= cpu_din[15:8];
		end else begin
			cpu_dout[15:8] <= ram_hi[cpu_a];
		end
	end
	always_ff @(posedge clk) begin
		if (cpu_wr_lo) begin
			ram_lo[cpu_a] <= cpu_din[7:0];
			cpu_dout[7:0] <= cpu_din[7:0];
		end else begin
			cpu_dout[7:0] <= ram_lo[cpu_a];
		end
	end

	// ---- 8M: VA13..VA7 for the MOB side (CPU address lines idle) ----------
	logic [24:1] m_i, m_o;
	always_comb begin
		m_i     = '0;
		m_i[1]  = vas[0];
		m_i[2]  = vas[1];
		m_i[10] = link_hi[4];
		m_i[11] = link_hi[5];
		m_i[13] = link_hi[6];
		m_i[14] = link_hi[7];
		m_i[23] = link_hi[8];
		m_i[21] = link_hi[9];
	end
	rampart_gal8m u_8m (.clk(clk), .ce(1'b0), .pin_i(m_i), .pin_o(m_o));

	wire [13:1] va = {m_o[22], m_o[20], m_o[19], m_o[18], m_o[17], m_o[16], m_o[15], va_lo};

	always_ff @(posedge clk) mob_q <= {ram_hi[va], ram_lo[va]};

	// ---- 4L: CPU wait (WAIT_MODEL = 1) ---------------------------------------
	generate
		if (WAIT_MODEL == 1) begin : g_wait
			logic [20:1] l_i, l_o;
			always_comb begin
				l_i    = '0;
				l_i[2] = ~half;          // hclk
				l_i[3] = pnxl;
				l_i[4] = 1'b0;           // mcx, not modelled
				l_i[5] = mosel_n;
				l_i[6] = cpu_as_n;
				l_i[7] = cpu_cyc;        // request pending
				l_i[8] = nxl;
				l_i[9] = ~vsync_n;
			end
			rampart_gal4l u_4l (.clk(clk), .ce(ce_14m), .pin_i(l_i), .pin_o(l_o));
			assign cpu_wait = cpu_cyc & ~l_o[18];
			/* verilator lint_off UNUSEDSIGNAL */
			wire unused_4l = &{1'b0, l_o[20:19], l_o[17:1]};
			/* verilator lint_on UNUSEDSIGNAL */
		end else begin : g_nowait
			assign cpu_wait = 1'b0;
			/* verilator lint_off UNUSEDSIGNAL */
			wire unused_w = &{1'b0, ce_14m, half, pnxl, nxl, vsync_n};
			/* verilator lint_on UNUSEDSIGNAL */
		end
	endgenerate

	/* verilator lint_off UNUSEDSIGNAL */
	wire unused_m = &{1'b0, m_o[24:23], m_o[21], m_o[14:1]};
	/* verilator lint_on UNUSEDSIGNAL */

endmodule
