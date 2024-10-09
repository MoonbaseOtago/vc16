.=0	
begin:
	j	start
	.=4	
	j	trap
	.=8
	j 	trap
	.=12
	j	trap
	.=16
	j	trap
	// leave room here for fast mmu trap handler
	.= 64
entry:	// code must be duplicated here at offset 64
	stio	a0, 6(a1) // turn off rom
	flush  icache	 // flush icache tags
	// code we load starts here 
	j	start

trap:	la	a0, trap_err
	jal	puts
	j	begin


putchr:	stio	a0, 2(a5)
1:		ldio	a0, 4(a5)
		and	a0, 1
		beqz	a0, 1b
	ret

puts:	mv	s1, lr
	mv	a3, a0
1:	lb	a0, (a3)
	beqz	a0, 2f
		add	a3, 1
		mv	a1, a0
		sub	a1, '\n'
		bnez	a1, 3f
			jal	putchr
			li	a0, '\r'
3:		jal	putchr
		j	1b

2:	jr	s1

puthex:	mv	s1, lr
	mv	a3, a0
	srl	a0, 4
	sub	a0, 10
	bgez	a0, 1f
		add a0, '0'+10
		j	2f
1:		add a0, 'a'
2:	jal	putchr
	mv	a0, a3
	and	a0, 0xf
	sub	a0, 10
	bgez	a0, 1f
		add a0, '0'+10
		j	2f
1:		add a0, 'a'
2:	mv	lr, s1
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

loop:	j loop

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
	la	a0, spi_cmd0
	li	a1, 6	// send
	jal	send_spi_1

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
4:		li	a1, 0xff
		stio    a1, 0(a4)
		sub	a3, 1
1:			ldio    a2, 4(a4)
			beqz    a2, 1b
		beqz	a3, 3f
		ldio	a0, 2(a4)
		sub	a1, a0
		beqz	a1, 4b
3:	
	ldio	a0, 0(a4)
	ret

cont:
	mv	s0, a0
	jal	puthex
	la	a0, lf_msg
	jal	puts

	li	s1, 0xff
	sub 	s1, s0
	sub	s0, 1
	beqz	s0, OK_spi
		beqz	s1, 1f
		j	start
1:		j	again
OK_spi:	

	la	a0, spi_cmd8
	li	a1, 6	// send
	jal	send_spi_1
	mv	s0, a0
	jal	puthex
	la	a0, lf_msg
	jal	puts

1:	j 1b
	








spi_cmd0:	
	.byte 0x40
	.byte 0x00
	.byte 0x00
	.byte 0x00
	.byte 0x00
	.byte 0x95
spi_cmd8:	
	.byte 0x48
	.byte 0x00
	.byte 0x00
	.byte 0x01
	.byte 0xaa
	.byte 0x0f
trap_err:	.string "trap error\n"
start_msg:	.string	"\nHello world!\n"
spi_init_msg:	.string	"SPI Init result: "
lf_msg:		.string	"\n"

end:
