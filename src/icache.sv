`define MULT 1
//
//	(C) Paul Campbell Moonbase Otago 2023-2024
//	All Rights Reserved

module icache(input clk, input reset,
		input  [PA-1:1]paddr,

		input	[3:0]dread,	
		input		 wstrobe_d,

		input		 flush_all,

		output  reg hit,
		output  reg pull,	// if not hit we need to read a line
		output  reg [PA-1:$clog2(LINE_LENGTH)]tag,
		output  reg[RV-1:0]rdata);

	parameter LINE_LENGTH=4;  // cache line length (in bytes)
	parameter NLINES=4;  // cache line length (in bytes)
	parameter RV=16;
	parameter PA=22;
	parameter USE_LATCHES_FOR_ICACHE=1;

	generate
		reg [LINE_LENGTH*8-1:0]r_data[0:NLINES-1];
		reg [PA-1:$clog2(LINE_LENGTH*NLINES)]r_tag[0:NLINES-1];
		reg [NLINES-1:0]r_valid;

		reg [$clog2(LINE_LENGTH*2)-1:0]r_offset, c_offset;
		genvar L, N; 

		reg match, valid;

		wire [$clog2(NLINES)-1:0]pindex = paddr[$clog2(LINE_LENGTH*NLINES)-1:$clog2(LINE_LENGTH)];
		wire [PA-1:$clog2(LINE_LENGTH*NLINES)]ptag = paddr[PA-1:$clog2(LINE_LENGTH*NLINES)];

		always @(*) begin 
			match = r_tag[pindex] == ptag;
			valid = r_valid[pindex];
			hit = valid && match;
			tag = {ptag, pindex};
			pull = !hit;
			c_offset = wstrobe_d? r_offset+1 : 0;
		end

		if (RV == 16) begin
			if (LINE_LENGTH == 4) begin
				always @(*)
				if (paddr[1]) begin
					rdata = r_data[pindex][31:16];
				end else begin
					rdata = r_data[pindex][15:0];
				end
			end
		end


		always @(posedge clk)
			r_offset <= c_offset;

		for (L = 0; L < NLINES; L=L+1) begin
			always @(posedge clk)
			if (reset || flush_all) begin
				r_valid[L] <= 0;
			end else
			if (wstrobe_d && (r_offset == (LINE_LENGTH*2-1)) && pindex == L)
				r_valid[L] <= 1;

			if (USE_LATCHES_FOR_ICACHE) begin

				for (N = 0; N < LINE_LENGTH*2; N=N+1) begin
					always_latch
					if (~clk && pindex == L && wstrobe_d && (r_offset) == (N^1)) begin
						r_data[L][N*4+3:N*4] = dread;
					end
				end
	
				always_latch
				if (~clk && pindex == L && wstrobe_d && r_offset == (LINE_LENGTH*2-1))
					r_tag[L] = ptag;

			end else begin

				for (N = 0; N < LINE_LENGTH*2; N=N+1) begin
					always @(posedge clk)
					if (pindex == L) 
					if (wstrobe_d && (r_offset) == (N^1)) begin
						r_data[L][N*4+3:N*4] <= dread;
					end
				end
	
				always @(posedge clk)
				if (pindex == L && wstrobe_d && r_offset == (LINE_LENGTH*2-1))
					r_tag[L] <= ptag;

			end
		end

//wire [31:0]rB = r_data['hb];
//wire [31:0]r1 = r_data[1];
//wire [31:0]r2 = r_data[2];
//wire [31:0]r3 = r_data[3];
	endgenerate

endmodule

/* For Emacs:
 * Local Variables:
 * mode:c
 * indent-tabs-mode:t
 * tab-width:4
 * c-basic-offset:4
 * End:
 * For VIM:
 * vim:set softtabstop=4 shiftwidth=4 tabstop=4:
 */

