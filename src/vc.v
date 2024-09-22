`define MULT 1
//
//	VC - minimal 32-bit C-only riscv - only has 8 regs
//	(C) Paul Campbell Moonbase Otago 2023-2024
//	All Rights Reserved
//
//	registers
//	    0   - 0   &
//		1 	- lr  *
//		2	- sp  *
//		3	- epc *+
//		4	- csr *+
//		5	- mmu *+
//		6   - kernel tmp *+
//		7	- mul_hi *
//		8	- s0
//		9	- s1
//		10 	- a0
//		11	- a1
//		12	- a2
//		13	- a3
//		14	- a4
//		15  - a5
//
//		(*) only accessable with lwsp/stsp and mv (and register specfic instructions), epc can be the source for an indirect jump
//		(+) only accessable from sup mode
//	
//
//	instructions:
//		C.LWSP
//		C.SWSP
//		C.LW
//		C.SW
//		C.J
//		C.JAL
//		C.JR
//		C.JALR
//		C.BEQZ
//		C.BNEZ
//		C.LI		**	constant is 8 bits sext
//		C.LUI		**  constant is 7 bits sext in 14:8
//		C.ADDI		**	constant is 8 bits sext
//		C.ADDIxSP	**  constant is 7 bits at 8:1 or 9:2 for 16/32 bits (aka "add sp, const")
//		C.ADDIxSPN	**  constant is 8 bits at 8:1 or 9:2 for 16/32 bits (aks "lea sp, const(sp)")
//		C.SLLI		(only by 1)
//		C.SRLI		(only by 1)
//		C.SRA		(only by 1)
//		C.ANDI	
//		C.MV
//		C.ADD		
//		C.AND
//		C.OR
//		C.XOR
//		C.SUB
//
//	new instructions
//		C.LB - replaces C.LD			
//		C.SB - replaces C.SD
//		C.LBSP - replaces C.LDSP		**
//		C.SBSP - replaces C.SDSP		**
//		C.LTZ 
//		C.GEZ
//		C.MUL		r, r
//		C.ADDB		r, r, r  sign extended
//		C.ADDBU		r, r, r  0 extended
//		C.SEXT
//		C.ZEXT
//		C.SYSCALL
//		C.SWAPSP
//		C.LUI		**  constant is 7 bits ~sext in 14:8
//
//	** extra bits
//		


module vc(input clk, input reset,
    input  wire [7:0] ui_in,    // Dedicated inputs - connected to the input switches
    output wire [7:0] uo_out,   // Dedicated outputs - connected to the 7 segment display
    input  wire [7:0] uio_in,   // IOs: Bidirectional Input path
    output wire [7:0] uio_out,  // IOs: Bidirectional Output path
    output wire [7:0] uio_oe    // IOs: Bidirectional Enable path (active high: 0=input, 1=output)
		);

	parameter RV=16;
	parameter PA=24;
	parameter VA=RV;
	parameter MMU=1;
	parameter NMMU=16;
	parameter LINE_LENGTH=4;  // cache line length (in bytes)
	parameter I_NLINES=16;  // number of lines
	parameter D_NLINES=8;  // number of lines
	parameter USE_LATCHES_FOR_MMU=1;
	parameter USE_LATCHES_FOR_ICACHE=1;
	parameter USE_LATCHES_FOR_DCACHE=1;

	reg			r_clk_invert;
	always @(posedge clk)
	if (reset)
		r_clk_invert <= ~ui_in[7];
	assign uo_out[2] = r_clk_invert^clk;

	wire [ 1:0]rstrobe;
	wire [(RV/8)-1:0]wmask;

	wire		mmu_reg_write;
	wire[RV-1:0]mmu_reg_data;
	wire[RV-1:0]mmu_read;
	wire		supmode;
	wire		mmu_enable;
	wire		mmu_d_proxy;
	wire		mmu_miss_fault, mmu_prot_fault;
	wire		mmu_fault;
	wire		ifetch;
	wire		is_read = (|rstrobe) && ~io_access;
	wire		is_write = (|wmask) && ~io_access;
	wire   [3:0]inv_mmu;
	wire [PA-1:1]phys_addr;
	wire [PA-1:1]phys_pc;
	generate
		if (MMU == 0) begin
			assign phys_addr = addr[VA-1:RV/16];
			assign phys_pc = pc[VA-1:RV/16];
			assign mmu_read = 'bx;
		end else begin
			mmu   #(.VA(VA), .PA(PA), .RV(RV), .NMMU(NMMU), .USE_LATCHES_FOR_MMU(USE_LATCHES_FOR_MMU))mmu(.clk(clk), .reset(reset), .supmode(supmode),
						.mmu_enable(mmu_enable),
						.mmu_d_proxy(mmu_d_proxy),
						.inv_mmu(inv_mmu),
						.is_pc(ifetch),
						.is_read(is_read),
						.is_write(is_write),
						.pcv(pc[VA-1:RV/16]),
						.addrv(addr[VA-1:RV/16]),
						.addrp(phys_addr),
						.pcp(phys_pc),
						.mmu_miss_fault(mmu_miss_fault),
						.mmu_prot_fault(mmu_prot_fault),
						.mmu_fault(mmu_fault),
						.reg_write(mmu_reg_write),
						.reg_data(mmu_reg_data),
						.reg_read(mmu_read));
		end
	endgenerate

	wire		fault;
	wire		jmp;
	wire		br; 
	wire   [2:0]cond;
	wire		trap;
	wire		sys_call;
	wire		swapsp;
	wire		load;
	wire		store; 
	wire		io; 
	wire   [3:0]op;
	wire   [3:0]rs1, rs2, rd;
	wire		needs_rs2; 
	wire		rs2_pc;
	wire [RV-1:0]imm;

	wire [VA-1:1]pc;
	wire [VA-1:RV/16]addr;
	wire [15:0]ins;
	wire		 iready;
`ifdef MULT
	wire		 mult;
	wire		 div;
`endif
	wire interrupt;
	
	wire		io_access; 
	wire		io_rdone=|rstrobe & io_access;
	wire		io_wdone=|wmask & io_access;
	wire		rdone, wdone;
	wire [RV-1:0]rdata, wdata;
	wire [7:0]uart_rdata;
	reg [RV-1:0]io_rdata;

	wire		i_flush_all;
	wire		d_flush_all;
	wire		do_flush_all;
	wire		flush_write;
	wire		do_flush_write;
	wire		do_inv_mmu;
	wire idone =ifetch&i_hit&!mmu_fault;
	wire		user_io;

	decode #(.RV(RV))dec(.clk(clk), .reset(reset),
		.supmode(supmode),
		.user_io(user_io),
		.ins(ins),
		.iready(iready),
		.idone(idone),
		.jmp(jmp),
		.br(br),
		.cond(cond),
		.trap(trap),
		.sys_call(sys_call),
		.swapsp(swapsp),
		.load(load),
		.store(store), 
		.io(io),
		.do_flush_all(do_flush_all),
		.do_flush_write(do_flush_write),
		.do_inv_mmu(do_inv_mmu),
`ifdef MULT
		.mult(mult),
		.div(div),
`endif
		.op(op),
		.rs1(rs1),
		.rs2(rs2),
		.rd(rd),
		.needs_rs2(needs_rs2), 
		.rs2_pc(rs2_pc), 
		.imm(imm));

	execute #(.VA(VA), .RV(RV), .NMMU(NMMU), .MMU(MMU))ex(.clk(clk), .reset(reset),
		.interrupt(interrupt),
		.pc(pc),
		.ifetch(ifetch),
		.iready(iready),
		.rstrobe(rstrobe),
		.idone(idone),
		.rdone(rdone),
		.wmask(wmask),
		.wdone(wdone),
		.io_access(io_access),
		.addr(addr),
		.wdata(wdata),
		.rdata(io_access?io_rdata:rdata),
		.jmp(jmp),
		.br(br),
		.cond(cond),
		.trap(trap),
		.sys_call(sys_call),
		.swapsp(swapsp),
		.load(load),
		.store(store), 
		.io(io),
		.do_flush_write(do_flush_write),
		.flush_write(flush_write),
		.do_flush_all(do_flush_all),
		.d_flush_all(d_flush_all),
		.i_flush_all(i_flush_all),
		.do_inv_mmu(do_inv_mmu),
		.inv_mmu(inv_mmu),
`ifdef MULT
		.mult(mult),
		.div(div),
`endif
		.mmu_reg_write(mmu_reg_write),
		.mmu_reg_data(mmu_reg_data),
		.mmu_read(mmu_read),
		.supmode(supmode),
		.user_io(user_io),
		.mmu_enable(mmu_enable),
		.mmu_d_proxy(mmu_d_proxy),
		.mmu_miss_fault(mmu_miss_fault),
		.mmu_prot_fault(mmu_prot_fault),
		.mmu_fault(mmu_fault),
		.fault(fault),
		.op(op),
		.rs1(rs1),
		.rs2(rs2),
		.rd(rd),
		.needs_rs2(needs_rs2), 
		.rs2_pc(rs2_pc), 
		.imm(imm));

	

	wire i_hit, i_pull;
	wire d_hit, d_push, d_pull, d_wdone;
	wire d_rstrobe_d, d_wstrobe_d, i_wstrobe_d;
	wire [PA-1:$clog2(LINE_LENGTH)]d_tag, i_tag;
	wire [3:0]dwrite;

	assign rdone =  |rstrobe && ((io_access ? io_rdone : d_hit && !(d_pull|d_push)) || fault);
	assign wdone =  |wmask &&   ((io_access ? io_wdone : ((d_hit && (!(d_pull|d_push)))|d_wdone) || (!d_push&&flush_write)) || fault);


	icache #(.PA(PA), .LINE_LENGTH(LINE_LENGTH), .RV(RV), .NLINES(I_NLINES), .USE_LATCHES_FOR_ICACHE(USE_LATCHES_FOR_ICACHE))icache(.clk(clk), .reset(reset),
		.paddr(phys_pc[PA-1:1]),

		.dread(uio_in[3:0]),	
		.wstrobe_d(i_wstrobe_d),

		.flush_all(i_flush_all),

		.hit(i_hit),
		.pull(i_pull),	// if not hit we need to read a line
		.tag(i_tag),
		.rdata(ins));

	dcache #(.PA(PA), .LINE_LENGTH(LINE_LENGTH), .RV(RV), .NLINES(D_NLINES), .USE_LATCHES_FOR_DCACHE(USE_LATCHES_FOR_DCACHE))dcache(.clk(clk), .reset(reset),
		.paddr(phys_addr),
		.read(io_access ? 2'b00: rstrobe ),
		.write(io_access ? 2'b00: wmask),
		.fault(fault),
		.wdata(wdata),

		.flush_all(d_flush_all),
		.flush_write(flush_write),

		.dread(uio_in[3:0]),	
		.wstrobe_d(d_wstrobe_d),
		.dwrite(dwrite),
		.rstrobe_d(d_rstrobe_d),

		.hit(d_hit),
		.push(d_push),	// if not hit we need to write a line
		.pull(d_pull),	// if not hit we need to read a line
		.wdone(d_wdone),
		.tag(d_tag),
		.rdata(rdata));

	wire [PA-1:$clog2(LINE_LENGTH)]ctag = ifetch?i_tag:d_tag;

	wire uart_intr;

	wire [1:0]rom_mode;
	reg [1:0]mem;
	always @(*) begin
		case (rom_mode)
		2'b00: mem = (ifetch?phys_pc[23]:phys_addr[23])? 2:0;
		2'b01: mem = 0;
		2'b10: mem = (ifetch?phys_pc[23]:phys_addr[23])? 1:0;
		2'b11: mem = (ifetch || !d_push)? 1:0;
		endcase
	end

	wire qspi_cs_2;
	qspi  #(.RV(RV), .LINE_LENGTH(LINE_LENGTH), .PA(PA))qspi(.clk(clk), .reset(reset),
		    .uio_oe(uio_oe[3:0]),
            .uio_out(uio_out[3:0]),
            .cs({qspi_cs_2, uo_out[1:0]}),

            .req((ifetch&i_pull)|(((|rstrobe || |wmask)&(d_pull|d_push))&!io_access&!fault)),
            .i_d(ifetch),
            .mem(mem),  
            .write(!ifetch && d_push),
            .paddr(ctag),

            .wstrobe_d(d_wstrobe_d),
            .wstrobe_i(i_wstrobe_d),
            .dwrite(dwrite),
            .rstrobe_d(d_rstrobe_d),

			.rom_mode(rom_mode),
            .reg_addr(addr[4:1]),
            .reg_data(wdata[7:0]),
            .reg_write(|wmask&&io_access&&!fault&&(addr[8:5]==0)));

	wire		uart_tx, uart_rx;
	uart		uart(.clk(clk), .reset(reset), 
					.rx(uart_rx),
					.tx(uart_tx),
					.interrupt(uart_intr),
					.io_addr(addr[4:1]),
					.io_write(|wmask&&io_access&&!fault&&(addr[8:5]==1)),
					.io_read(rstrobe[0]&&io_access&&!fault&&(addr[8:5]==1)),
					.io_wdata(wdata[7:0]),
					.io_rdata(uart_rdata));

	wire		spi_intr;
	wire   [1:0]spi_miso, spi_mosi, spi_clk;
    wire   [2:0]spi_cs;
	wire   [7:0]spi_rdata;
	spi			spi(.clk(clk), .reset(reset),
             
					.cs(spi_cs),
					.spi_clk(spi_clk),
					.miso(spi_miso),
					.mosi(spi_mosi),

					.interrupt(spi_intr),

					.reg_addr(addr[3:1]),
					.reg_sel(addr[5:4]),
					.reg_write(|wmask&&io_access&&!fault&&(addr[8:6]==3)),
					.reg_read(|rstrobe&&io_access&&!fault&&(addr[8:6]==3)),
					.reg_data_in(wdata[7:0]),
					.reg_data_out(spi_rdata));

	wire		gpio_intr;
	wire   [7:0]gpio_rdata;
	gpio		gpio(.clk(clk), .reset(reset),
					.ui_in(ui_in),
					.uo_out(uo_out[7:3]),
					.uio_in(uio_in[7:4]),
					.uio_out(uio_out[7:4]),
					.uio_oe(uio_oe[7:4]),

					.interrupt(gpio_intr),

					.uart_rx(uart_rx),
					.uart_tx(uart_tx),

					.spi_cs(spi_cs),
					.spi_clk(spi_clk),
					.spi_miso(spi_miso),
					.spi_mosi(spi_mosi),

					.qspi_cs(qspi_cs_2),

					.reg_addr(addr[5:1]),
					.reg_write(|wmask&&io_access&&!fault&&(addr[8:6]==2)),
					.reg_data_in(wdata[7:0]),
					.reg_data_out(gpio_rdata));

	

	wire [15:0]intr_rdata;
	intr		intr(.clk(clk), .reset(reset),
					.interrupt(interrupt),
					.uart_intr(uart_intr),
					.spi_intr(spi_intr),
					.gpio_intr(gpio_intr),
					.io_addr(addr[4:1]),
					.io_write(|wmask&&io_access&&!fault&&(addr[8:5]==2)),
					.io_wdata(wdata[15:0]),
					.io_rdata(intr_rdata));

	always @(*)
	case (addr[8:5])
	0:			io_rdata = 16'hx; // qspi
	1:			io_rdata = {8'h0, uart_rdata};
	2:			io_rdata = intr_rdata;
	4:			io_rdata = {8'h0, gpio_rdata};
	5:			io_rdata = {8'h0, gpio_rdata};
	6:			io_rdata = {8'h0, spi_rdata};
	7:			io_rdata = {8'h0, spi_rdata};
	default:	io_rdata = 16'hx;
	endcase
 

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
