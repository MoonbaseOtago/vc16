//
//	(C) Moonbase Otago 2024
//	All Rights Reserved
//
//
//	This is a ROM bootstrap that runs at first reset on a VC 16-bit
//
//	It runs with the default memory mapping, the MMU is off, all memory reads
//	go to ROM, all memory writes will go to RAM - this means that this code 
//	cannot use memory for storing anything (no stack, no saving return addresses
//	etc etc) everything has to run in registers
//
//	This code initialises an SDCARD and reads the first N blocks into RAM and then jumps
//	to that code
//

.=0	
begin:
	js	start
	.=4	
	js	trap
	.=8
	js 	trap
	.=12
	js	trap
	.=16
	js	trap
	// leave room here for fast mmu trap handler
	.= 64
entry:	// code must be duplicated here at offset 64
	stio	a0, 6(a1) // turn off rom
	flush  icache	 // flush icache tags
	// code we load starts here 

trap:	la	a0, trap_err
	jal	puts
	j	begin


putchr:	stio	a0, 2(a5)
1:		ldio	a0, 4(a5)
		and	a0, 1
		beqz	a0, 1b
	ret

puts:	mv	s1, lr
	mv	s0, a0
1:	lb	a0, (s0)
	beqz	a0, 2f
		add	s0, 1
		mv	a1, a0
		sub	a1, '\n'
		bnez	a1, 3f
			jal	putchr
			li	a0, '\r'
3:		jal	putchr
		j	1b

2:	jr	s1

puthex:	
	mv	a1, a0
	srl	a0, 4
	sub	a0, 10
	bgez	a0, 1f
		add a0, '0'+10
		j	2f
1:		add a0, 'a'
2:	stio    a0, 2(a5)
8:              ldio    a0, 4(a5)
                and     a0, 1
                beqz    a0, 8b
	mv	a0, a1
	and	a0, 0xf
	sub	a0, 10
	bgez	a0, 1f
		add a0, '0'+10
		j	2f
1:		add a0, 'a'
2:	
	j	putchr


copyrom:	lw	a2, (a0)
		sw	a2, (a0)
		add	a0, 2
		add	a1, -1
	 	bnez 	a1, copyrom
	ret

start:
	li	a5, 0x20	// 0x20 - uart base
	li	a0, 108		// 50000000/115200/4 
	stio	a0, 8(a5)
	srl	a0, 8
	stio	a0, 10(a5)

	la	a0, start_msg
	jal	puts

// set up spi

again:
setup_spi:
	//
	//	clk = out 5
	//	cs0 = out 3
	//	miso = in 1
	//	mosi = out 4
	li	a4, 0xa0	// gpio base+0x20
	li	a0, 0x60	// o 3/2 = cs0/-
	stio	a0, 2(a4)
	li	a0, 0x42	// o 5/4 = clk/mosi
	stio	a0, 4(a4)
	li	a4, 0x90	// gpio base+0x10
	li	a0, 0x01	// set miso_0 in from in 1
	stio	a0, 6(a4)

	li	a4, 0xc0
	li	a0, 0x00	// spi[0], mode 0, io 0
	stio	a0, 8(a4)	
	li	a0, 125		// 400kHz
	stio	a0, 10(a4)	// spi[0] clock

reset_spi:
// send SPI reset
	li	a0, -1
	li	a4, 0xf0
	li	a2, 12
2:		stio	a0, 0(a4)
1:			ldio	a1, 4(a4)
			beqz	a1, 1b
		sub	a2, 1
		bnez	a2, 2b
	ldio	a0, 0(a4)    // end
reset_spi_done:

	la	a0, spi_init_msg
	jal	puts

	li	a4, 0xc0
	li	a0, -1
	stio	a0, 14(a4)

1:	la	a0, spi_cmd0
	li	a1, 6	// send
	jal	send_spi_1

	li	s1, 0xff
	sub 	s1, a0
	beqz	s1, 1b

	j	cont

send_spi_1:
2:
	lb	a2, (a0)
	stio    a2, 0(a4)
	add	a0, 1
	sub	a1, 1
1:		ldio    a2, 4(a4)
		beqz    a2, 1b
	bnez	a1, 2b
read_spi:
	li	a3, 10
	li	a1, 0xff
	stio    a1, 2(a4)	// put the spi into sd searching mode
1:		ldio    a2, 4(a4)
		beqz    a2, 1b
	ldio	a0, 0(a4)
	ret

cont:
	mv	a3, a0
	jal	puthex
	la	a0, lf_msg
	jal	puts

	li	s1, 0xff
	sub 	s1, a3
	sub	a3, 1
	beqz	a3, OK_spi
		beqz	s1, 1f
		j	start
1:		j	again
OK_spi:	

	la	a0, spi_cmd8
	li	a1, 6	// send
	jal	send_spi_1
	mv	a3, a0
	jal	puthex
	la	a0, lf_msg
	jal	puts

initing:
	la	a0, spi_cmd55
	li	a1, 6	// send
	jal	send_spi_1
	mv	a3, a0
	jal	puthex
	la	a0, lf_msg
	jal	puts
cmd41:
	la	a0, spi_acmd41
	li	a1, 6	// send
	jal	send_spi_1
	mv	a3, a0
	jal	puthex
	la	a0, lf_msg
	jal	puts

	li	a1, 0xff
	sub	a1, a3
	beqz	a1, 1f
		bnez	a3, initing	// waiting for it to go to 0
		j	1f
2:
		la	a0, spi_cmd1
		li	a1, 6	// send
		jal	send_spi_1
		mv	a3, a0
		jal	puthex
		la	a0, lf_msg
		jal	puts

		bnez    a3, 2b

1:
	li	a0, 4		// 2.5MHz
	stio	a0, 10(a4)	// spi[0] clock

	la	a0, spi_cmd16
	li	a1, 6	// send
	jal	send_spi_1
	mv	a3, a0
	jal	puthex
	la	a0, lf_msg
	jal	puts
	
	li	a2, 0		// memory address
	li	a3, 0		// block counter

1:		la	a0, bl_msg
		jal	puts
		mv	a0, a3
		jal	puthex
		la	a0, cl_msg
		jal	puts

		jal	read_block

		jal	puthex
		la	a0, lf_msg
		jal	puts

		add	a3, 1
		li	a0, 20		// number of 512 byte blocks to load
		sub	a0, a3
		bnez	a0, 1b

	jal	go_boot
	


read_block:	// a3 is block number
	li	a0, 0x40+17
	stio    a0, 0(a4)
1:		ldio    a0, 4(a4)
		beqz    a0, 1b

	li	a1, 0
	stio    a1, 0(a4)
1:		ldio    a0, 4(a4)
		beqz    a0, 1b

	stio    a1, 0(a4)
1:		ldio    a0, 4(a4)
		beqz    a0, 1b

	mv	a0, a3
	srl	a0, 8
	stio    a0, 0(a4)
1:		ldio    a0, 4(a4)
		beqz    a0, 1b

	stio    a3, 0(a4)
1:		ldio    a0, 4(a4)
		beqz    a0, 1b

	li	a0, 1
	stio    a0, 0(a4)
1:		ldio    a0, 4(a4)
		beqz    a0, 1b

rd:
	li	a1, 0xff
	stio    a1, 2(a4)	// put the spi into sd searching mode
1:		ldio    a0, 4(a4)
		beqz    a0, 1b
	ldio	a0, 2(a4)
	bnez	a0, 9f
		
2:	stio    a1, (a4)	
1:		ldio    a0, 4(a4)
		beqz    a0, 1b
	ldio	a0, 2(a4)
	li	s0, 0xff
	sub	s0, a0
	beqz	s0, 2b

	sub	s0, 1
	bnez	s0, 9f

	li	s1, 512
3:
		stio    a1, (a4)	
1:			ldio    a0, 4(a4)
			beqz    a0, 1b
		ldio	a0, 2(a4)
		sb	a0, (a2)
		add	a2, 1
		sub	s1, 1
		bnez	s1, 3b

		stio    a1, (a4)		// toss crc
1:			ldio    a0, 4(a4)
			beqz    a0, 1b
		stio    a1, (a4)	
1:			ldio    a0, 4(a4)
			beqz    a0, 1b
	
	
9:	ldio	a1, 0(a4)	// drop cs
	ret






go_boot:
	la	a0, loaded_msg
	jal	puts
	li	a0, 64
	li	a1, 0
	li	a2, 4
fl:		flush	(a1)	// flush dcache data to sram
		add	a1, a2
		add	a0, -1
		bnez	a0, fl	
aaa:
	flush	dcache	// flush dcache tags
bbb:
	li	a0, 0
	li	a1, 0x00 // qspi base
	j	entry	// and switch the mapping and flush the icache

spi_cmd0:	
	.byte 0x40
	.byte 0x00
	.byte 0x00
	.byte 0x00
	.byte 0x00
	.byte 0x95
spi_cmd1:	
	.byte 0x41
	.byte 0x40
	.byte 0x00
	.byte 0x00
	.byte 0x00
	.byte 0x87
spi_cmd8:	
	.byte 0x48
	.byte 0x00
	.byte 0x00
	.byte 0x01
	.byte 0xaa
	.byte 0x87
spi_cmd16:	
	.byte 0x50
	.byte 0x00
	.byte 0x00
	.byte 0x02
	.byte 0x00
	.byte 0x01
spi_acmd41:	
	.byte 0x69
	.byte 0x40
	.byte 0x10
	.byte 0x00
	.byte 0x00
	.byte 0x65
spi_cmd55:	
	.byte 0x77
	.byte 0x00
	.byte 0x00
	.byte 0x00
	.byte 0x00
	.byte 0x01
trap_err:	.string "trap error\n"
start_msg:	.string	"\nBooting looking for sdcard .... \n"
spi_init_msg:	.string	"SPI Init result: "
loaded_msg:	.string	"Loaded - booting into code ...\n"
bl_msg:		.string	"read block "
cl_msg:		.string	": "
lf_msg:		.string	"\n"

end:
