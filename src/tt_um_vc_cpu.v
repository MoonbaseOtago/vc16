`default_nettype wire

module tt_um_vc32_cpu (
    input  wire [7:0] ui_in,    // Dedicated inputs - connected to the input switches
    output wire [7:0] uo_out,   // Dedicated outputs - connected to the 7 segment display
    input  wire [7:0] uio_in,   // IOs: Bidirectional Input path
    output wire [7:0] uio_out,  // IOs: Bidirectional Output path
    output wire [7:0] uio_oe,   // IOs: Bidirectional Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

	parameter RV=16;
	parameter VA=16;
	parameter PA=24;
	parameter MMU=1;
	parameter NMMU=16;
	parameter I_NLINES=8;  // number of lines   
	parameter D_NLINES=8;  // number of lines
	parameter USE_LATCHES_FOR_MMU=0;
	parameter USE_LATCHES_FOR_ICACHE=0;
	parameter USE_LATCHES_FOR_DCACHE=0;
	
	reg r_reset;
	always @(posedge clk)
		r_reset <= ~rst_n;

	vc   #(.RV(RV), .VA(VA), .PA(PA), .MMU(MMU), .NMMU(NMMU), .I_NLINES(I_NLINES), .D_NLINES(D_NLINES),
.USE_LATCHES_FOR_MMU(USE_LATCHES_FOR_MMU), .USE_LATCHES_FOR_ICACHE(USE_LATCHES_FOR_ICACHE), .USE_LATCHES_FOR_DCACHE(USE_LATCHES_FOR_DCACHE))cpu(.clk(clk), .reset(r_reset|!ena), 
			.ui_in      (ui_in),    // Dedicated inputs
        		.uo_out     (uo_out),   // Dedicated outputs
        		.uio_in     (uio_in),   // IOs: Input path
        		.uio_out    (uio_out),  // IOs: Output path
        		.uio_oe     (uio_oe));   // IOs: Enable path (active high: 0=input, 1=output)


endmodule
