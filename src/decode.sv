`define MULT 1
//
//	(C) Paul Campbell Moonbase Otago 2023-2024
//	All Rights Reserved
//

`define OP_ADD	0
`define OP_SUB	1
`define OP_XOR	2
`define OP_OR	3
`define OP_AND	4
`define OP_SLL	5
`define OP_SRA	6
`define OP_SRL	7
`define OP_ADDB	8
`define OP_ADDBU 9
`define OP_SWAP 10

module decode(input clk, input reset,
	    input [15:0]ins, 
		input idone,
		input supmode,
		input user_io,

		output iready,
		output jmp,
		output br, 
		output [2:0]cond,
		output trap,
		output sys_call,
		output swapsp,
		output load,
		output store, 
		output io, 
		output do_flush_all, 
		output do_flush_write, 
		output do_inv_mmu, 
		output set_cc, 
`ifdef MULT
		output mult,
		output div,
`endif
		output [3:0]op,
		output [3:0]rs1, output[3:0]rs2, output [3:0]rd,
		output needs_rs2, 
		output rs2_pc, 
		output rs2_inv, 
		output [RV-1:0]imm);

	parameter RV=32;	// register width

	reg		r_ready; assign iready = r_ready;
	always @(posedge clk)
		r_ready <= idone&!reset;
	reg		r_trap, c_trap; assign trap = r_trap;
	reg		r_sys_call, c_sys_call; assign sys_call = r_sys_call;
	reg		r_swapsp, c_swapsp; assign swapsp = r_swapsp;
	reg		r_load, c_load; assign load = r_load;
	reg		r_io, c_io; assign io = r_io;
	reg		r_store, c_store; assign store = r_store;
	reg[2:0]r_cond, c_cond; assign cond = r_cond;
	reg		r_jmp, c_jmp; assign jmp = r_jmp;
	reg		r_br, c_br; assign br = r_br;
	reg[3:0]r_op, c_op; assign op = r_op;
	reg[3:0]r_rs1, c_rs1; assign rs1 = r_rs1;
	reg[3:0]r_rs2, c_rs2; assign rs2 = r_rs2;
	reg[3:0]r_rd, c_rd; assign rd = r_rd;
	reg		r_needs_rs2, c_needs_rs2; assign needs_rs2 = r_needs_rs2;
	reg		r_rs2_pc, c_rs2_pc; assign rs2_pc = r_rs2_pc;
	reg		r_rs2_inv, c_rs2_inv; assign rs2_inv = r_rs2_inv;
	reg[RV-1:0]r_imm, c_imm; assign imm = r_imm;
`ifdef MULT
	reg		r_mult, c_mult; assign mult = r_mult;
	reg		r_div, c_div; assign div = r_div;
`endif
	reg		r_flush_all, c_flush_all; assign do_flush_all = r_flush_all;
	reg		r_flush_write, c_flush_write; assign do_flush_write = r_flush_write;
	reg		r_inv_mmu, c_inv_mmu; assign do_inv_mmu = r_inv_mmu;
	reg		r_set_cc, c_set_cc; assign set_cc = r_set_cc;

	always @(*) begin
		c_flush_all = 0;
		c_flush_write = 0;
		c_trap = 0;
		c_load = 0;
		c_io = 0;
		c_store = 0;
		c_cond = 3'bx;
		c_needs_rs2 = 0;
		c_op = 4'bx;
		c_rs1 = 4'bx;
		c_rs2 = 4'bx;
		c_rd = 4'h0;
		c_imm = {RV{1'bx}};
		c_jmp = 0;
		c_br = 0;
		c_sys_call = 0;
		c_swapsp = 0; 
		c_rs2_pc = 0;
		c_rs2_inv = 0;
		c_inv_mmu = 0;
		c_set_cc = 0;
`ifdef MULT
		c_mult = 0;
		c_div = 0;
`endif
		case (ins[1:0])  // synthesis full_case parallel_case
		2'b00:
			case (ins[15:13]) // synthesis full_case parallel_case
			3'b000: begin	// addi4sp
						c_op = `OP_ADD;
						c_trap = ins[11:2]==0;
						if (RV == 16) begin
							c_imm = {{(RV-9){1'b0}}, ins[9:7],ins[5],ins[12:10],ins[6],1'b0};
						end else begin
							c_imm = {{(RV-10){1'b0}}, ins[9:7],ins[5],ins[12:10],ins[6],2'b0};
						end
						c_rd = {1'b1, ins[4:2]};
						c_rs1 = 2;
					end
			3'b010: begin 	// lw
						c_load = 1;
						c_op = `OP_ADD;
						c_cond = 3'bxx0;
						c_rd = {1'b1, ins[4:2]};
						c_rs1 = {1'b1, ins[9:7]};
						if (RV==16) begin
							c_imm = {{(RV-6){1'b0}}, ins[5], ins[12:10],ins[6], 1'b0};
						end else begin
							c_imm = {{(RV-7){1'b0}}, ins[5], ins[12:10],ins[6], 2'b0};
						end
				    end
			3'b011: begin 	// lb
						c_load = 1;
						c_op = `OP_ADD;
						c_cond = 3'bxx1;
						c_rd = {1'b1, ins[4:2]};
						c_rs1 = {1'b1, ins[9:7]};
						if (RV==16) begin
							c_imm = {{(RV-5){1'b0}},         ins[12:10],ins[6], ins[5]};
						end else begin
							c_imm = {{(RV-5){1'b0}},         ins[11:10],ins[6], ins[12], ins[5]};
						end
					end
			3'b100:	begin	// jalr   x(lr)
						c_br = 1;
						c_cond = 3'b1x1;
						c_op = `OP_ADD;
						c_imm = {{(RV-7){ins[4]}}, ins[3:2],  ins[12:10], ins[6], 1'b0};
						c_rd = 1;
						c_rs1 = 1;
						c_trap = (|ins[9:7])|ins[5];
					end
			3'b110: begin 	// sw
						c_store = 1;
						c_cond = 3'bxx0;
						c_op = `OP_ADD;
						c_rs2 = {1'b1, ins[4:2]};
						c_rs1 = {1'b1, ins[9:7]};
						if (RV==16) begin
							c_imm = {{(RV-6){1'b0}}, ins[5], ins[12:10],ins[6], 1'b0};
						end else begin
							c_imm = {{(RV-7){1'b0}}, ins[5], ins[12:10],ins[6], 2'b0};
						end
					end
			3'b111: begin 	// sb
						c_store = 1;
						c_cond = 3'bxx1;
						c_op = `OP_ADD;
						c_rs2 = {1'b1, ins[4:2]};
						c_rs1 = {1'b1, ins[9:7]};
						if (RV==16) begin
							c_imm = {{(RV-5){1'b0}},         ins[12:10],ins[6], ins[5]};
						end else begin
							c_imm = {{(RV-5){1'b0}},         ins[11:10],ins[6], ins[12], ins[5]};
						end
					end
			default: c_trap = 1;
			endcase
		2'b01:casez (ins[15:13]) // synthesis full_case parallel_case
			3'b000:	begin	// addi **
						c_op = `OP_ADD;
						c_rs1 = {1'b1, ins[9:7]};
						c_rd = {1'b1, ins[9:7]};
						c_imm = {{(RV-7){ins[4]}}, ins[3:2],  ins[12:10], ins[6:5]};
					end
			3'b001:	begin	// jal
						c_br = 1;
						c_cond = 3'b1x1;
						c_op = `OP_ADD;
						c_imm = {{(RV-11){ins[12]}}, ins[8], ins[10:9], ins[6],ins[7],ins[2],ins[11],ins[5:3],1'b0};			
						c_rd = 1;
						c_rs1 = 0;
					end
			3'b010:	begin	// li
						c_op = `OP_ADD;
						c_rs1 = 0;
						c_rd = {1'b1, ins[9:7]};
						c_imm = {{(RV-7){ins[4]}}, ins[3:2],  ins[12:10], ins[6:5]};
					end
			3'b011:	if (ins[10:7] == 2) begin	// addi4sp  ** 
						c_op = `OP_ADD;
						c_rd = 2;
						c_rs1 = 2;
						if (RV==16) begin
							c_imm = {{(RV-7){ins[4]}},ins[3:2],ins[12:11],ins[5],ins[6],1'b0};
						end else begin
							c_imm = {{(RV-8){ins[4]}},ins[3:2],ins[12:11],ins[5],ins[6],2'b00};
						end
					end else begin				// lui **
						c_op = `OP_ADD;
						c_rd = ins[10:7];
						c_rs1 = 0;
						c_imm = {{(RV-14){ins[11]}}, ins[12], ins[6:2],8'b0};
						c_trap = !supmode && (c_rd >= 4'b0011 && c_rd <= 4'b0110);
					end
			3'b100:	begin
						c_rd = {1'b1, ins[9:7]};
						c_rs1 = {1'b1, ins[9:7]};
						c_rs2 = {1'b1, ins[4:2]};
						c_imm = {{(RV-6){1'b0}}, ins[2], ins[12], ins[4:3], ins[6:5]};
						case (ins[11:10]) // synthesis full_case parallel_case
						2'b00: begin c_op = `OP_SRL; c_needs_rs2 = ins[12]; c_trap = !ins[12]?ins[2]:(ins[6:5]!=0); end
						2'b01: begin c_op = `OP_SRA; c_needs_rs2 = ins[12]; c_trap = !ins[12]?ins[2]:(ins[6:5]!=0); end
						2'b10: c_op = `OP_AND;
						2'b11: begin
								c_needs_rs2 = 1;
								case ({ins[12],ins[6:5]}) // synthesis full_case parallel_case
								3'b0_00:	c_op = `OP_SUB;
								3'b0_01:	c_op = `OP_XOR;
								3'b0_10:	c_op = `OP_OR;
								3'b0_11:	c_op = `OP_AND;
								3'b1_00:	begin c_op = `OP_SUB; c_set_cc = 1; end
								3'b1_01:	begin c_op = `OP_ADD; c_set_cc = 1; end
								default: c_trap = 1;
								endcase
							   end
						endcase
					end
			3'b101:	begin	// j
						c_br = 1;
						c_cond = 3'b1x0;
						c_op = `OP_ADD;
						c_imm = {{(RV-11){ins[12]}}, ins[8], ins[10:9], ins[6],ins[7],ins[2],ins[11],ins[5:3],1'b0};
						c_rs1 = 0;
					end
			3'b11?:	begin	//  beqz/bnez
						c_br = 1;
						c_cond = {2'b00, ins[13]};	// beqz/bnez
						c_op = `OP_ADD;
						c_rs1 = {1'b1, ins[9:7]};
						c_imm =  {{(RV-8){ins[12]}},ins[6:5],ins[2],ins[11:10],ins[4:3],1'b0};
					end
			default: c_trap = 1;
			endcase
		2'b10:
			casez (ins[15:13])  // synthesis full_case parallel_case
			3'b000:	begin	// slli
						c_op = `OP_SLL;
						c_rd = {1'b1, ins[9:7]};
						c_rs1 = {1'b1, ins[9:7]};
						c_rs2 = {1'b1, ins[4:2]};
						c_imm = {{(RV-6){1'b0}}, ins[2], ins[12], ins[4:3], ins[6:5]};
						c_needs_rs2 = ins[12]; c_trap = !ins[12]?ins[2]:(ins[6:5]!=0);
					end
			3'b001:	begin	// addi (rx)
						c_op = `OP_ADD;
						c_rs1 = {1'b0, ins[9:7]};
						c_rd = {1'b0, ins[9:7]};
						c_imm = {{(RV-7){ins[4]}}, ins[3:2],  ins[12:10], ins[6:5]};
						c_trap = !supmode && (c_rd >= 4'b0011 && c_rd <= 4'b0110);
					end
			3'b010:	begin	// lwsp  **
						c_load = 1;
						c_cond = 3'bxx0;
						c_op = `OP_ADD;
						c_rd = ins[10:7];
						c_rs1 = 2;
						if (RV == 16) begin
							c_imm = {{(RV-8){1'b0}}, ins[4:2], ins[12:11], ins[5],ins[6], 1'b0};
						end else begin
							c_imm = {{(RV-9){1'b0}}, ins[4:2], ins[12:11], ins[5],ins[6], 2'b0};
						end
						c_trap = !supmode && (c_rd >= 4'b0011 && c_rd <= 4'b0110);
					end
			3'b011:	begin	// lbsp  **
						c_load = 1;
						c_cond = 3'bxx1;
						c_op = `OP_ADD;
						c_rd = ins[10:7];
						c_rs1 = 2;
						if (RV == 16) begin
							c_imm = {{(RV-7){1'b0}},          ins[3:2], ins[12:11],ins[5], ins[6], ins[4]};
						end else begin
							c_imm = {{(RV-7){1'b0}},          ins[2],   ins[12],ins[6:4], ins[11], ins[3]};
						end
						c_trap = !supmode && (c_rd >= 4'b0011 && c_rd <= 4'b0110);
					end
			3'b100:	if (!ins[12]) begin
						if (ins[6:2] == 0) begin	// jr
							c_jmp = 1;
							c_op = `OP_ADD;
							c_cond = 3'bxx0;
							c_rs1 = ins[10:7];
							c_rs2 = 0;
							c_needs_rs2 = 1;
							c_trap = !supmode && (c_rs1 >= 4'b0011 && c_rs1 <= 4'b0110);
						end else begin	// mv
							c_op = `OP_ADD;
							c_rd = ins[10:7];
							c_rs1 = 0;
							c_rs2 = ins[5:2];
							c_needs_rs2 = 1;
							c_trap = !supmode && ((c_rs2 >= 4'b0011 && c_rs2 <= 4'b0110) || (c_rs1 >= 4'b0011 && c_rs1 <= 4'b0110));
						end
					end else begin
						if (ins[6:2] == 0) begin	// jalr
							c_trap = ins[10:7]==0; 
							c_jmp = 1;
							c_cond = 3'bxx1;
							c_op = `OP_ADD;
							c_rd = 1;
							c_rs1 = ins[10:7];
							c_rs2 = 0;
							c_needs_rs2 = 1;
							c_trap = !supmode && (c_rs1 >= 4'b0011 && c_rs1 <= 4'b0110);
						end else begin	// add
							c_op = `OP_ADD;
							c_rd = ins[10:7];
							c_rs1 = ins[10:7];
							c_rs2 = ins[5:2];
							c_needs_rs2 = 1;
							c_trap = !supmode && ((c_rs2 >= 4'b0011 && c_rs2 <= 4'b0110) || (c_rs1 >= 4'b0011 && c_rs1 <= 4'b0110));
						end
					end
			3'b110:	begin	// swsp  **
						c_store = 1;
						c_cond = 3'bxx0;
						c_rs2 = ins[10:7];
						c_op = `OP_ADD;
						c_rs1 = 2;
						if (RV == 16) begin
							c_imm = {{(RV-8){1'b0}}, ins[4:2], ins[12:11], ins[5],ins[6], 1'b0};
						end else begin
							c_imm = {{(RV-9){1'b0}}, ins[4:2], ins[12:11], ins[5],ins[6], 2'b0};
						end
						c_trap = !supmode && (c_rs2 >= 4'b0011 && c_rs2 <= 4'b0110);
					end
			3'b111:	begin	// sbsp  **
						c_store = 1;
						c_cond = 3'bxx1;
						c_rs2 = ins[10:7];
						c_rs1 = 2;
						c_op = `OP_ADD;
						if (RV == 16) begin
							c_imm = {{(RV-7){1'b0}},          ins[3:2], ins[12:11],ins[5], ins[6], ins[4]};
						end else begin
							c_imm = {{(RV-7){1'b0}},          ins[2],   ins[12],ins[6:4], ins[11], ins[3]};
						end
						c_trap = !supmode && (c_rs2 >= 4'b0011 && c_rs2 <= 4'b0110);
					end
			default: c_trap = 1;
			endcase
		2'b11:	casez (ins[15:13]) // synthesis full_case parallel_case
			3'b000:	begin	//  
						c_needs_rs2 = 1;
						casez (ins[12:2]) // synthesis full_case parallel_case
						11'b0??: begin				// trap instructions (use 01 for break)
									c_sys_call = 0;
									c_trap = 1;
							   end
						11'b0101:begin				// syscall
									c_sys_call = 1;
									c_trap = 1;
							   end
						11'b0110:begin				// swapsp
									c_op = `OP_ADD;
									c_trap = !supmode;
									c_rd = 2;
									c_rs1 = 6;
									c_rs2 = 0;
									c_swapsp = 1;
								 end
						11'b010??:begin				// flush all
									c_rd = 0;
									c_flush_all = 1;
									c_imm = {{(RV-2){1'bx}}, ins[3:2]};
									c_trap = !supmode;
							   end
						11'b01????:begin			// invmmu  si sd ui ud
									c_rd = 0;
									c_inv_mmu = supmode;
									c_imm = {{(RV-4){1'bx}}, ins[5:2]};
									c_trap = !supmode;
								end
						default: c_trap = 1;
						endcase
				    end
			3'b001: begin 	// swio
						c_store = 1;
						c_io = 1;
						c_cond = 3'bxx0;
						c_op = `OP_ADD;
						c_rs2 = {1'b1, ins[4:2]};
						c_rs1 = {1'b1, ins[9:7]};
						c_imm = {{(RV-4){1'b0}}, ins[11:10],ins[6], 1'b0};
						c_trap = !supmode && !user_io;
					end
			3'b010: begin 	// lwio
						c_load = 1;
						c_io = 1;
						c_op = `OP_ADD;
						c_cond = 3'bxx0;
						c_rd = {1'b1, ins[4:2]};
						c_rs1 = {1'b1, ins[9:7]};
						c_imm = {{(RV-4){1'b0}}, ins[11:10],ins[6], 1'b0};
						c_trap = !supmode && !user_io;
				    end
			3'b011:
					begin				// lui ** - note inverted extension
						c_op = `OP_ADD;
						c_rd = ins[10:7];	// allows lr
						c_rs1 = 0;
						c_imm = {{(RV-15){~ins[11]}}, ins[11],  ins[12], ins[6:2],8'b0};
						c_trap = !supmode && (c_rd >= 4'b0011 && c_rd <= 4'b0110);
					end
			3'b100:	begin
						c_rd = {1'b1, ins[9:7]};
						c_rs1 = {1'b1, ins[9:7]};
						c_rs2 = {1'b1, ins[4:2]};
						c_imm = {{(RV-6){1'b0}}, ins[2], ins[12], ins[4:3], ins[6:5]};
						case (ins[11:10]) // synthesis full_case parallel_case
						2'b10: c_op = `OP_OR;
						2'b11: begin
								c_needs_rs2 = 1;
								case ({ins[12],ins[6:5]}) // synthesis full_case parallel_case
`ifdef MULT
								3'b0_00:	c_mult = 1;
								3'b0_01:	c_div = 1;
`endif
								3'b0_10:	c_op = `OP_ADDB;
								3'b0_11:	c_op = `OP_ADDBU;
								3'b1_00:	c_op = `OP_SWAP; // swap 
								3'b1_01:	case (ins[4:2])
											3'b000: begin c_op = `OP_ADD; c_rs2_pc = 1; c_rs2 = 4'bx; end	// addpc								
											3'b001: begin c_op = `OP_ADDB; c_rs2 = 0; end   // sext
											3'b010: begin c_op = `OP_ADDBU; c_rs2 = 0; end   // zext
											3'b011: begin c_op = `OP_XOR; c_rs2 = 0; c_rs2_inv = 1; end   // inv
											3'b100: begin c_op = `OP_SUB; c_rs1 = 0; c_rs2 =  {1'b1, ins[9:7]}; end   // neg
											default:	c_trap = 1;
											endcase
								default:	c_trap = 1;
								endcase
							   end
						default: c_trap = 1;
						endcase
					end
			3'b101: begin 	// flushw (reg)
						c_store = 1;
						c_flush_write = 1;
						c_io = 0;
						c_cond = 3'bxx0;
						c_op = `OP_ADD;
						c_rs2 = 0;
						c_rs1 = {1'b1, ins[9:7]};
						c_imm = 0;
						c_trap = !supmode ||  ins[12:10] != 0 || ins[6:2] != 0 ;// other encodings availa
					end
			3'b11?:	begin	//  bltz/bgez
						c_br = 1;
						c_cond = {2'b01, ins[13]};	// bltz/bgez
						c_rs1 = {1'b1, ins[9:7]};
						c_op = `OP_ADD;
						c_imm =  {{(RV-8){ins[12]}},ins[6:5],ins[2],ins[11:10],ins[4:3],1'b0};
					end
			default: c_trap = 1;
		    endcase
		endcase
	end

	always @(posedge clk) 
	if (idone) begin
		r_trap <= c_trap;
		r_sys_call <= c_sys_call;
		r_swapsp <= c_swapsp;
		r_rs1 <= c_rs1;
		r_rs2 <= c_rs2;
		r_needs_rs2 <= c_needs_rs2;
		r_rs2_pc <= c_rs2_pc;
		r_rs2_inv <= c_rs2_inv;
		r_rd <= c_rd;
		r_imm <= c_imm;
		r_store <= c_store;
		r_load <= c_load;
		r_io <= c_io;
`ifdef MULT
		r_mult <= c_mult;
		r_div <= c_div;
`endif
		r_op <= c_op;
		r_br <= c_br;
		r_cond <= c_cond;
		r_jmp <= c_jmp;
		r_flush_all <= c_flush_all;
		r_flush_write <= c_flush_write;
		r_inv_mmu <= c_inv_mmu;
		r_set_cc <= c_set_cc;
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

