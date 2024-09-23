`define MULT 1
//
//	(C) Paul Campbell Moonbase Otago 2023-2024
//	All Rights Reserved
//

module mmu(input clk,  input reset, input is_pc, input is_write, input is_read, input mmu_enable, input mmu_d_proxy, input supmode,
			input [VA-1:RV/16]pcv,
			input [VA-1:RV/16]addrv, 
			output [PA-1:RV/16]addrp,
			output [PA-1:RV/16]pcp,
			output		   mmu_miss_fault,
			output		   mmu_prot_fault,
			input		   mmu_fault,
			input	 [3:0]inv_mmu,		// si sd ui ud
			input		   reg_write,		
			output[RV-1:0]reg_read,
			input [RV-1:0]reg_data);

	parameter RV=16;
	parameter PA=RV;
	parameter VA=RV;
	parameter NMMU=8;
	parameter USE_LATCHES_FOR_MMU=1;

	parameter UNTOUCHED = VA-$clog2(NMMU);
	reg [VA-1: UNTOUCHED]r_fault_address;
	reg				     r_fault_type;
	reg				     r_fault_ins;
	reg				     r_fault_sup;
	assign reg_read =  {r_fault_address, {(RV-(VA-UNTOUCHED)-4){1'b0}}, r_fault_ins, r_fault_sup, r_fault_type, 1'b0};

//
//	mmu reg
//
//	write virt:
//
//	15-X upper bits phys address
//  2 - writeable
//	1 - valid
//  0 - 1
//
//	write phys:

//	15-X upper bits virtual fault address
//	3	fault_ins
//	2	fault_sup
//	1	fault_type	1 valid fault 0 write fault
//	0 - 0
//
//	read:
//
//	15-X upper bits virtual fault address
//	3	fault_ins
//	2	fault_sup
//	1	fault_type	1 valid fault 0 write fault
//	0   0
//
//	

	reg [2*NMMU-1:0]r_valid_i;
	reg [2*NMMU-1:0]r_valid_d;
	reg             r_writeable_d[0:2*NMMU-1];
	wire [$clog2(NMMU):0]sel_i = {supmode, pcv[VA-1:UNTOUCHED]};
	wire [$clog2(NMMU):0]sel_d = {supmode&~(mmu_d_proxy&~is_pc), addrv[VA-1:UNTOUCHED]};

	wire mmu_miss_fault_i = mmu_enable && is_pc && !r_valid_i[sel_i];
	wire mmu_miss_fault_d = mmu_enable && (is_read | is_write) && !r_valid_d[sel_d];
	assign mmu_miss_fault = mmu_miss_fault_i|mmu_miss_fault_d;
	assign mmu_prot_fault = mmu_enable && is_write && !r_writeable_d[sel_d[VA-UNTOUCHED:0]];
	reg [PA-1:UNTOUCHED]r_vtop_i[0:2*NMMU-1];
	reg [PA-1:UNTOUCHED]r_vtop_d[0:2*NMMU-1];

	assign pcp = {(mmu_enable ? r_vtop_i[sel_i]:{{PA-RV{1'b0}}, pcv[VA-1:UNTOUCHED]}), pcv[UNTOUCHED-1:RV/16]};
	assign addrp = {(mmu_enable ? r_vtop_d[sel_d]:{{PA-RV{1'b0}}, addrv[VA-1:UNTOUCHED]}), addrv[UNTOUCHED-1:RV/16]};

	wire [$clog2(NMMU):0]reg_addr = {r_fault_sup, r_fault_address[VA-1:UNTOUCHED]};

	always @(posedge clk)
	if (reset) begin
		r_valid_i <= 0;
		r_valid_d <= 0;
		r_fault_type <= 0;
		r_fault_ins <= 0;
		r_fault_sup <= 0;
	end else
	if (mmu_fault) begin
		r_fault_address <= (mmu_miss_fault_i?pcv[VA-1:UNTOUCHED]:addrv[VA-1:UNTOUCHED]);
		r_fault_type <= mmu_miss_fault;
		r_fault_ins <= is_pc;
		r_fault_sup <= supmode&~(mmu_d_proxy&~is_pc);
	end else
	if (|inv_mmu) begin
		if (inv_mmu[3]) // si
			r_valid_i[{1'b1, {VA-UNTOUCHED{1'b1}}}:{1'b1, {VA-UNTOUCHED{1'b0}}}] <= 0;
		if (inv_mmu[2]) // sd
			r_valid_d[{1'b1, {VA-UNTOUCHED{1'b1}}}:{1'b1, {VA-UNTOUCHED{1'b0}}}] <= 0;
		if (inv_mmu[1]) // ui
			r_valid_i[{1'b0, {VA-UNTOUCHED{1'b1}}}:{1'b0, {VA-UNTOUCHED{1'b0}}}] <= 0;
		if (inv_mmu[0]) // ud
			r_valid_d[{1'b0, {VA-UNTOUCHED{1'b1}}}:{1'b0, {VA-UNTOUCHED{1'b0}}}] <= 0;
	end else
	if (reg_write) begin
		if (reg_data[0]) begin
			if (r_fault_ins) begin
				r_valid_i[reg_addr] <= reg_data[1];
			end else begin
				r_valid_d[reg_addr] <= reg_data[1];
			end
			r_fault_address <= r_fault_address+1;
		end else begin
			r_fault_address <= reg_data[VA-1:UNTOUCHED];
			r_fault_type <= reg_data[1];
			r_fault_sup <= reg_data[2];
			r_fault_ins <= reg_data[3];
		end
	end 

	generate
		if (USE_LATCHES_FOR_MMU) begin
			genvar I;

			for (I = 0; I < (2*NMMU); I=I+1) begin
				always_latch
				if (~clk && reg_write && reg_data[0] && r_fault_ins && reg_addr==I) 
					r_vtop_i[I] = reg_data[RV-1:RV-(PA-UNTOUCHED)];
	
				always_latch
				if (~clk && reg_write && reg_data[0] && !r_fault_ins && reg_addr==I) begin
					r_vtop_d[I] = reg_data[RV-1:RV-(PA-UNTOUCHED)];
					r_writeable_d[I] = reg_data[2];
				end
			end

		end else begin
			always @(posedge clk)
			if (reg_write) begin
				if (reg_data[0]) begin
					if (r_fault_ins) begin
						r_vtop_i[reg_addr] <= reg_data[RV-1:RV-(PA-UNTOUCHED)];
					end else begin
						r_vtop_d[reg_addr] <= reg_data[RV-1:RV-(PA-UNTOUCHED)];
						r_writeable_d[reg_addr] <= reg_data[2];
					end
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

