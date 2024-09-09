`define MULT 1
//
//	(C) Paul Campbell Moonbase Otago 2023-2024
//	All Rights Reserved
//
module gpio(input clk, input reset,
		input  [7:0]ui_in,	
		input  [7:4]uio_in,	
		output [7:4]uio_out,	
		output [7:4]uio_oe,	
		output [7:3]uo_out,	

		output      interrupt,

		input		uart_tx,
		output		uart_rx,

		output [1:0]spi_miso,
		input  [1:0]spi_mosi,
		input  [1:0]spi_clk,
		input  [2:0]spi_cs,

		inout       qspi_cs,
			
		input	[4:0]reg_addr,
		input   [7:0]reg_data_in,
		output  reg[7:0]reg_data_out,
		input	     reg_write);

	
		reg	[2:0]r_uart_rx_src;
		assign	 uart_rx = ui_in[r_uart_rx_src];

		reg [3:0]r_spi_miso_src[0:1];
		wire [15:0]miso = {uio_in, 4'bx, ui_in};
		assign spi_miso[0] = miso[r_spi_miso_src[0]];
		assign spi_miso[1] = miso[r_spi_miso_src[1]];

		reg	 [7:3]r_gpio_o;
		reg	 [7:4]r_gpio_io;
		reg	 [7:4]r_gpio_en;
		assign uio_oe = r_gpio_en;

		reg	 [3:0]r_src_o[3:7];
		reg	 [3:0]r_src_io[4:7];

		//
		//	registers:
		//
		//	0:1  pending
		//	2:3  status
		//	5:4  enable
		//	9:8	 out
		//	10	 oe[7:4]
		//	11	 miso_src/uart_rx_src
		//  16	 -/-  			        src0 = gpio
		//  17	 srco3/-				src1 = uart_tx
		//  18	 srco5/srco4			src2 = spi_mosi[0]
		//  19	 srco7/srco6			src3 = spi_mosi[1]
		//  22	 srcio5/srco4			src4 = spi_clk[0]
		//  23	 srcio7/srco6			src5 = spi_clk[1]
		//								src6 = spi_cs[0]
		//								src7 = spi_cs[1]
		//								src8 = spi_cs[2]
		//								src11 = qspi_cs[2]

		reg [7:0]r_enable_in;
		reg [7:4]r_enable_io;
		wire [7:0]pending_in = ui_in&r_enable_in;
		wire [7:4]pending_io = uio_in&r_enable_io;
		assign interrupt = (|pending_in) | (|pending_io);
		always @(*) 
		case (reg_addr) 
		0: reg_data_out = pending_in;
		1: reg_data_out = {pending_io[7:4], 4'b0};
		2: reg_data_out = ui_in;
		3: reg_data_out = {uio_in[7:4], 4'b0};
		4: reg_data_out = r_enable_in;
		5: reg_data_out = {r_enable_io, 4'b0};
		8:reg_data_out = {r_gpio_o, 3'b0};
		9:reg_data_out = {r_gpio_io, 4'b0};
		10:reg_data_out = {r_gpio_en, 4'b0};
		11:reg_data_out = {r_spi_miso_src[1], r_spi_miso_src[0]};
		12:reg_data_out = {4'b0, 1'b0, r_uart_rx_src};
		16:reg_data_out = 0;
		17:reg_data_out = {r_src_o[3],  4'b0};
		18:reg_data_out = {r_src_o[5],  r_src_o[4]};
		19:reg_data_out = {r_src_o[7],  r_src_o[6]};
		22:reg_data_out = {r_src_io[5], r_src_io[4]};
		23:reg_data_out = {r_src_io[7], r_src_io[6]};
		default: reg_data_out = 8'bx;
		endcase

		always @(posedge clk) 
		if (reset) begin
			r_enable_in <= 0;
			r_enable_io <= 0;
			r_gpio_en <= 0;
			r_uart_rx_src <= 0;
			r_src_o[6] <= 1;
		end else
		if (reg_write)
		case (reg_addr) // synthesis full_case parallel_case
		4: r_enable_in <= reg_data_in;
		5: r_enable_io <= reg_data_in[7:4];
		8: r_gpio_o <= reg_data_in[7:3];
		9: r_gpio_io <= reg_data_in[7:4];
		10: r_gpio_en <= reg_data_in[7:4];
		11: begin r_spi_miso_src[1] <= reg_data_in[7:4]; r_spi_miso_src[0] <= reg_data_in[3:0]; end
		12: r_uart_rx_src <= reg_data_in[2:0]; 
		17: begin r_src_o[3] <= reg_data_in[7:4]; end
		18: begin r_src_o[5] <= reg_data_in[7:4]; r_src_o[4] <= reg_data_in[3:0]; end
		19: begin r_src_o[7] <= reg_data_in[7:4]; r_src_o[6] <= reg_data_in[3:0]; end
		22: begin r_src_io[5] <= reg_data_in[7:4]; r_src_io[4] <= reg_data_in[3:0]; end
		23: begin r_src_io[7] <= reg_data_in[7:4]; r_src_io[6] <= reg_data_in[3:0]; end
		endcase

		wire [15:1]srcs = {4'bx, qspi_cs, 2'bx, spi_cs, spi_clk, spi_mosi, uart_tx};
		generate 

			genvar I;

			for (I = 3; I < 8; I=I+1) begin
				wire [15:0]srcs_o = {srcs, r_gpio_o[I]};
				assign uo_out[I] = srcs_o[r_src_o[I]];
			end
			for (I = 4; I < 8; I=I+1) begin
				wire[15:0]srcs_io = {srcs, r_gpio_io[I]};
				assign uio_out[I] = srcs_io[r_src_io[I]];
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

