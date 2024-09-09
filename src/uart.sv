//	(C) Paul Campbell Moonbase Otago 2023-2024
//	All Rights Reserved

module uart(input clk, input reset, 
		output interrupt,
		
		output	tx,
		input	rx,

		input	[3:0]io_addr,
		input	[7:0]io_wdata,
		input		 io_write,
		output	reg[7:0]io_rdata,
		input		 io_read);


	parameter BAUD=115200;
	parameter CLOCK=20000000;

	reg [11:0]r_div;
	wire is_zero = r_div == 0;
	reg [11:0]r_div_value;
	reg [7:0]r_in, r_out;
	reg [6:0]r_ib;

	reg [3:0]r_xstate, r_rstate;
	reg [1:0]r_xcnt, r_rcnt;
	reg		 r_x_invert, r_r_invert;

	reg r_r_int, r_x_int;
	assign interrupt = r_r_int|r_x_int;

	reg r_x, r_r;

	assign tx = r_x;

	always @(posedge clk)
		r_r <= rx;

	wire r = r_r^r_r_invert;

	always @(posedge clk)
	if (reset) begin
		r_rstate <= 0;
	end else
	case (r_rstate) 
	0:	if (!r) begin
			r_rstate <= 1;
			r_rcnt <= 1;
		end
	1:	if (is_zero) begin
			if (r_rcnt == 0) begin
				if (!r) begin
					r_rstate <= 2;
					r_rcnt <= 3;
				end else begin
					r_rstate <= 0;
				end
			end else begin
				r_rcnt <= r_rcnt-1;
			end
		end 
	2, 3, 4, 5, 6, 7, 8:
		if (is_zero) begin
			if (r_rcnt == 0) begin
				r_ib <= {r,r_ib[6:1]};
				r_rstate <= r_rstate+1;
				r_rcnt <= 3;
			end else begin
				r_rcnt <= r_rcnt-1;
			end
		end
	9:	if (is_zero) begin
			if (r_rcnt == 0) begin
				r_in <= {r, r_ib};
				r_rcnt <= 3;
				r_rstate <= 10;
			end else begin
				r_rcnt <= r_rcnt-1;
			end
		end
	10:	if (is_zero) begin
			if (r_rcnt == 0) begin
				r_rstate <= 0;
			end else begin
				r_rcnt <= r_rcnt-1;
			end
		end
	default:;
	endcase

	always @(posedge clk)
	if (reset) begin
		r_r_int <= 0;
	end else 
	if (r_rstate == 9 && is_zero && r_rcnt == 0) begin
		r_r_int <= 1;
	end else
	if (io_write && io_addr == 2 && io_wdata[1]) begin
		r_r_int <= 0;
	end else
	if (io_read && io_addr == 0) begin
		r_r_int <= 0;
	end

	always @(posedge clk)
	if (reset) begin
		r_xstate <= 0;
		r_x <= 1^r_x_invert;
		r_x_int <= 0;
	end else
	case (r_xstate)
	0: if (io_write) begin
			r_x <= 1^r_x_invert;
			case (io_addr) 
			1:	begin
					r_xstate <= 1;
					r_out <= io_wdata;
					r_x_int <= 0;
				end
			2:  begin
					if (io_wdata[0])
						r_x_int <= 0;
				end
			default:;
			endcase
		end else begin
			r_x <= 1^r_x_invert;
		end
	1:  if (is_zero) begin
			r_xcnt <= 3;
			r_x <= 0^r_x_invert;// start bit
			r_xstate <= 2;
		end
	2, 3, 4, 5, 6, 7, 8, 9: 
		if (is_zero)
		if (r_xcnt == 0) begin
			r_xstate <= r_xstate+1;
			r_xcnt <= 3;
			r_x <= r_out[0]^r_x_invert;
			r_out <= {1'bx, r_out[7:1]};
		end else begin
			r_xcnt <= r_xcnt-1;
		end
	10:	if (is_zero)
		if (r_xcnt == 0) begin
			r_xstate <= 11;
			r_xcnt <= 3;
			r_x <= 1^r_x_invert;
			r_x_int <= 1;
		end else begin
			r_xcnt <= r_xcnt-1;
		end
	11:	if (io_write && io_addr == 1) begin
			r_xstate <= (is_zero && r_xcnt == 0? 1:12);
			r_out <= io_wdata;
			r_x_int <= 0;
		end else begin
			if (io_write && io_addr == 2 && io_wdata[0])
				r_x_int <= 0;
			r_x <= 1^r_x_invert;
			if (is_zero)
			if (r_xcnt == 0) begin
				r_xstate <= 0;
			end else begin
				r_xcnt <= r_xcnt-1;
			end
		end
	12: begin
			r_x <= 1^r_x_invert;
			if (is_zero)
			if (r_xcnt == 0) begin
				r_xstate <= 1;
			end else begin
				r_xcnt <= r_xcnt-1;
			end
		end
	default:;
	endcase

	always @(*) begin
		case (io_addr) 
		0: io_rdata = r_in;
		2: io_rdata = {6'b0, r_r_int, r_x_int};
		3: io_rdata = {6'b0, r_r_invert, r_x_invert};
		4: io_rdata = r_div_value[7:0];
		5: io_rdata = {4'b0,r_div_value[11:8]};
		default: io_rdata = 8'bx;	
		endcase
	end

	always @(posedge clk)
	if (reset) begin
		r_div_value <= 1; //CLOCK/BAUD/4;	// 1 for testing
		r_r_invert <= 0;
		r_x_invert <= 0;
	end else
	if (io_write) begin
		case (io_addr)
		3:  begin r_r_invert <= io_wdata[1]; r_x_invert <= io_wdata[0]; end
		4:	r_div_value[7:0] <= io_wdata;
		5:	r_div_value[11:8] <= io_wdata[3:0];
		default: ;
		endcase
	end

	always @(posedge clk)
	if (reset || r_div == 0) begin
		r_div <= r_div_value;
	end else begin
		r_div <= r_div-1;
	end


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

