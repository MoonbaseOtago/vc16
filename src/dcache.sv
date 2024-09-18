// 
//  (C) Paul Campbell Moonbase Otago 2023-2024 
//  All Rights Reserved
//
module dcache(input clk, input reset,
		input  [PA-1:1]paddr,
		input	[1:0]write,
		input	[1:0]read,
		input	fault,
		input  [RV-1:0]wdata,

		input		 flush_all,
		input		 flush_write,

		input	[3:0]dread,	
		input		 wstrobe_d,
		output	reg[3:0]dwrite,
		input		 rstrobe_d,

		output  hit,
		output  push,	// if not hit we need to write a line
		output  pull,	// if not hit we need to read a line
		output  wdone,
		output  [PA-1:$clog2(LINE_LENGTH)]tag,
		output  reg[RV-1:0]rdata);

	parameter LINE_LENGTH=4;  // cache line length (in bytes)
	parameter NLINES=4;  // cache line length (in bytes)
	parameter RV=16;
	parameter PA=22;
	parameter USE_LATCHES_FOR_DCACHE=0;

	generate
		reg [LINE_LENGTH*8-1:0]r_data[0:NLINES-1];
//wire [LINE_LENGTH*8-1:0]r0=r_data['h19];
//wire [LINE_LENGTH*8-1:0]r1=r_data[1];
//wire [LINE_LENGTH*8-1:0]r3=r_data[3];
		reg [PA-1:$clog2(LINE_LENGTH*NLINES)]r_tag[0:NLINES-1];
		reg [NLINES-1:0]r_dirty;
		reg [NLINES-1:0]r_valid;

		reg [$clog2(LINE_LENGTH*2)-1:0]r_offset, c_offset;
		genvar L, N; 

		wire match, valid, dirty;

		wire [$clog2(NLINES)-1:0]pindex = paddr[$clog2(LINE_LENGTH*NLINES)-1:$clog2(LINE_LENGTH)];
		wire [PA-1:$clog2(LINE_LENGTH*NLINES)]ptag = paddr[PA-1:$clog2(LINE_LENGTH*NLINES)];

		assign match = r_tag[pindex] == ptag;
		assign valid = r_valid[pindex];
		assign dirty = r_dirty[pindex];
		assign hit = valid && match;
		assign push = valid && dirty && !fault && (flush_write ? 1 : !match);
		assign pull = !hit && !push && !flush_write;
		assign tag = {pull?ptag:r_tag[pindex], pindex};

		always @(*) begin 
			c_offset = wstrobe_d|rstrobe_d ? r_offset+1 : 0;
		end

		wire [LINE_LENGTH*8-1:0]r = r_data[pindex];
		if (LINE_LENGTH == 4) begin
			always @(*)
			case (r_offset)
			0: dwrite = r[7:4];
			1: dwrite = r[3:0];
			2: dwrite = r[15:12];
			3: dwrite = r[11:8];
			4: dwrite = r[23:20];
			5: dwrite = r[19:16];
			6: dwrite = r[31:28];
			7: dwrite = r[27:24];
			endcase
		end
		
	
		if (RV == 16) begin
			if (LINE_LENGTH == 4) begin
				always @(*)
				if (read != 2'b11) begin
					case ({paddr[1],read[1]})
					0: rdata = {8'bx, r_data[pindex][7:0]};
					1: rdata = {8'bx, r_data[pindex][15:8]};
					2: rdata = {8'bx, r_data[pindex][23:16]};
					3: rdata = {8'bx, r_data[pindex][31:24]};
					endcase
				end else begin
					if (paddr[1]) begin
						rdata = r_data[pindex][31:16];
					end else begin
						rdata = r_data[pindex][15:0];
					end
				end
			end
		end

		always @(posedge clk)
			r_offset <= c_offset;

		assign wdone = !reset && |write && !fault && (wstrobe_d && (r_offset == (2*LINE_LENGTH-1)));

		for (L = 0; L < NLINES; L=L+1) begin
			always @(posedge clk)
			if (pindex == L && wstrobe_d && r_offset == (LINE_LENGTH*2-1))
				r_tag[L] <= ptag;

			always @(posedge clk)
			if (reset || flush_all) begin
				r_valid[L] <= 0;
			end else
			if (flush_write && rstrobe_d && (r_offset == (LINE_LENGTH*2-1)) && pindex == L) begin
				r_valid[L] <= 0;
			end else
			if (wstrobe_d && (r_offset == (LINE_LENGTH*2-1)) && pindex == L)
				r_valid[L] <= 1;

			always @(posedge clk)
			if (pindex == L)
			if (|write && hit && !flush_write && !fault && (!pull && !push)) begin
				r_dirty[L] <= 1;
			end else
			if (r_offset == (LINE_LENGTH*2-1)) begin
				case ({rstrobe_d, wstrobe_d})
				2'b10: r_dirty[L] <= 0;
				2'b01: r_dirty[L] <= |write && !flush_write;
				default:;
				endcase
			end

			for (N = 0; N < LINE_LENGTH*2; N=N+1) begin
				always @(posedge clk)
				if (|write && !flush_write &&  pindex == L && !fault && ((hit && (!pull || !push)) || (wstrobe_d && r_offset == (2*LINE_LENGTH-1))) && (write != 2'b11 ? {paddr[1], write[1]} == N[2:1] : paddr[1] == N[2])) begin
					casez ({write, N[1:0]}) // synthesis full_case parallel_case
					4'b01_?0: r_data[L][N*4+3:N*4] <= wdata[3:0];
					4'b10_?0: r_data[L][N*4+3:N*4] <= wdata[3:0];
					4'b01_?1: r_data[L][N*4+3:N*4] <= wdata[7:4];
					4'b10_?1: r_data[L][N*4+3:N*4] <= wdata[7:4];
					4'b11_00: r_data[L][N*4+3:N*4] <= wdata[3:0];
					4'b11_01: r_data[L][N*4+3:N*4] <= wdata[7:4];
					4'b11_10: r_data[L][N*4+3:N*4] <= wdata[11:8];
					4'b11_11: r_data[L][N*4+3:N*4] <= wdata[15:12];
					default:  ;
					endcase
				end else
				if (wstrobe_d && r_offset == (N^1) && pindex == L) begin
					r_data[L][N*4+3:N*4] <= dread;
				end
			end
		end
			
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

