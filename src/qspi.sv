`define MULT 1
//
//	(C) Paul Campbell Moonbase Otago 2023-2024
//	All Rights Reserved
//
module qspi(input clk, input reset,
			output [3:0]uio_oe,	
			output [3:0]uio_out,	
			output [2:0]cs,

			input	    req,
			input	    i_d,
			input	[1:0]mem,
			input		write,
			input [PA-1:$clog2(LINE_LENGTH)]paddr,

			output		wstrobe_d,
			output		wstrobe_i,
			input	[3:0]dwrite,
			output	    rstrobe_d,
	
			output	[1:0]rom_mode, 
			input	[3:0]reg_addr,
			input   [7:0]reg_data,
			input	     reg_write);

	parameter LINE_LENGTH=4;  // cache line length (in bytes)
	parameter PA=24;
	parameter RV=16;

	reg [3:0]r_read_delay[0:2];
	reg      [2:0]r_quad;
	reg      [2:0]r_mask;
	//
	//	rom mode:
	//
	//	00 - 8mb CS0 - 8MB CS2
	//  01 - 8Mb CS0 
	//  10 - 16Mb CS0 - 8MB ROM CS2
	//	11 - 8/16Mb CS0 - ROM CS2 overlay 
	reg	     [1:0]r_rom_mode;
	assign rom_mode = r_rom_mode;
	wire force_23_0 = r_rom_mode != 2'b01;

	reg		[2:0]r_cs, c_cs;	
	reg		[3:0]r_uio_out, c_uio_out;
	reg		[1:0]r_uio_oe, c_uio_oe;
	reg			 r_ind, c_ind;
	assign cs = r_cs;
	assign	uio_oe = {r_uio_oe[1], r_uio_oe[1], r_uio_oe};
	assign	uio_out = r_uio_out;
	
	generate

		always @(posedge clk)
		if (reset) begin
			r_read_delay[0] <= 4;	// 5 clocks for RAM 
			r_read_delay[1] <= 4;	// 5 clocks for ROM
			r_read_delay[2] <= 4;	// 5 clocks for RAM 
			r_mask <= 3'b010;
			r_quad <= 3'b101;
			r_rom_mode <= 2'b11;
		end else
		if (reg_write) begin
			if (reg_addr[1:0] == 3) begin
				r_rom_mode <= reg_data[1:0];
			end else begin
				r_read_delay[reg_addr[1:0]] <= reg_data[3:0];
				r_mask[reg_addr[1:0]] <= reg_data[7];
				r_quad[reg_addr[1:0]] <= reg_data[6];
			end
		end

		reg [4:0]r_state, c_state;
		reg [4:0]r_count, c_count;
		reg r_rstrobe_d, c_rstrobe_d; assign rstrobe_d = r_rstrobe_d;
		reg r_wstrobe_i, c_wstrobe_i; assign wstrobe_i = r_wstrobe_i;
		reg r_wstrobe_d, c_wstrobe_d; assign wstrobe_d = r_wstrobe_d;

		always @(posedge clk) begin
			r_state <= (reset? 0:c_state);
			r_cs <= (reset? 3'b111:c_cs);	
			r_uio_out <= c_uio_out;
			r_uio_oe <= (reset?0:c_uio_oe);
			r_count <= c_count;
			r_ind <= reset?0:c_ind;
			r_rstrobe_d <= c_rstrobe_d;
			r_wstrobe_i <= c_wstrobe_i;
			r_wstrobe_d <= c_wstrobe_d;
		end

		wire [6:0]const_38 = 7'h38;
		wire [6:0]const_eb = 7'h6b;
		wire [6:0]const_35 = 7'h35;
		wire [6:0]const_ab = 7'h2b;

		always @(*) begin
			c_ind = r_ind;
			c_state = r_state;
			c_uio_oe = r_uio_oe;
			c_uio_out = r_uio_out;
			c_cs = r_cs;
			c_count = r_count;
			c_rstrobe_d = 0;
			c_wstrobe_i = 0;
			c_wstrobe_d = 0;
			case (r_state)	// synthesis full_case parallel_case
			31: if (req)
			   if (r_quad[mem]) begin
					c_state = 1;
					c_cs[mem] = 0;
					c_uio_oe = 2'b11;
					if (write) begin
						c_uio_out = 4'h3;
					end else begin
						c_uio_out = 4'he;
					end
			   end else begin
					c_state = 2;
					c_cs[mem] = 0;
					c_uio_oe = 2'b01;
					if (write) begin
						c_uio_out = 4'bxxx0;
					end else begin
						c_uio_out = 4'bxxx1;
					end
					c_count = 6;
			   end
			 1:begin
					c_state = 9;
					if (write) begin
						c_uio_out = 4'h8;
					end else begin
						c_uio_out = 4'hb;
					end
			   end
			2: begin
					if (r_count == 0) begin
						c_state = 9;
					end
					if (write) begin
						c_uio_out = {3'bxxx, const_38[r_count[2:0]]};
					end else begin
						c_uio_out = {3'bxxx, const_eb[r_count[2:0]]};
					end
					c_count = r_count-1;
			   end
			9: begin
					c_state = 10;
					c_uio_oe = 2'b11;
					c_uio_out = {{(24-PA){1'b0}}, paddr[PA-1:20]}&{~force_23_0, 3'b000};
			   end
			10:begin
					c_state = 11;
					c_uio_out = paddr[19:16];
			   end
			11:begin
					c_state = 12;
					c_uio_out = paddr[15:12];
			   end
			12:begin
					c_state = 13;
					c_uio_out = paddr[11:8];
			   end
			13:begin
					c_state = 14;
					c_uio_out = paddr[7:4];
			   end
			14:begin
					c_state = (write? 15 : 17);
					c_rstrobe_d = write;
					c_count = 2*LINE_LENGTH-1;
					c_uio_out = {paddr[3:$clog2(LINE_LENGTH)], {$clog2(LINE_LENGTH){1'b0}}};
			   end
			15:begin		
					if (r_count == 0) begin
						c_state = 16;
					end else begin
						c_rstrobe_d = 1;
					end
					c_uio_out = dwrite;
					c_count = r_count-1;
			   end
			16:begin
					c_state = 31;
					c_cs = 3'b111;
					c_uio_oe = 2'b00;
			   end
			17:begin
					c_state = 18;
					if (r_mask[mem]) begin
						c_uio_out = 4'hf;
					end else begin
						c_uio_oe = 2'b00;
					end
			   end
			18:begin
					c_state = 19;
					c_count = {1'b0, r_read_delay[mem]};
			   end
			19:begin
					if (r_count == 0) begin
						c_count = 2*LINE_LENGTH-1;
						c_state = 20;
						c_wstrobe_i = i_d;
						c_wstrobe_d = ~i_d;
					end else begin
						c_count = r_count - 1;
					end
					c_uio_oe = 2'b00;
			   end
			20:begin
					if (r_count == 0) begin
						c_cs = 3'b111;
						c_state = 31;
					end else begin
						c_wstrobe_i = i_d;
						c_wstrobe_d = ~i_d;
					end
					c_count = r_count - 1;
			   end

			0: begin
					c_cs = r_ind? 3'b010: 3'b000;	// send ab to power up then optionally 35 to 0 to go into quad mode
					c_uio_oe = 2'b01;
					c_uio_out = {3'bxxx, ~r_ind};
					c_count = 6;
					c_state = 21;
			   end
		    21:begin
					if (r_count == 0) begin
						c_state = 22;
					end
					c_count = r_count-1;
					c_uio_out = {3'bxxx, (r_ind?const_35[r_count[2:0]]:const_ab[r_count[2:0]])};
			   end
		    22:begin
					c_state = (r_ind?31:0);
					c_ind = 1;
					c_uio_oe = 2'b00;
					c_cs = 3'b111;
			   end
			endcase
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

