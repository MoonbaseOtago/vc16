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
trap:	li	a0, 'Z'
	jal	send
x:	j	x

send:	stio	a0, 2(a5)
sn1:		ldio	a0, 4(a5)
		and	a0, 1
		beqz	a0, sn1
	ret


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

	li	a0, 'A'
//	jal	send

	la	a0, begin
	la	a1, end
	srl	a1, 1
	jal	copyrom

	li	a0, 'B'
//	jal	send
uu:
	li	a0, 64
	li	a1, 0
	li	a2, 4
fl:		flush	(a1)	// flush dcache data
		add	a1, a2
		add	a0, -1
		bnez	a0, fl	
aaa:
	flush	dcache	// flush dcache tags
bbb:
	li	a0, 0
	li	a1, 0x00 // spi base
	stio	a0, 6(a1) // turn off rom
ccc:
	flush  icache	// flush icache tags

//switch to ram

ddd:
	li	a0, 'C'
//	jal	send


	la	a2, test
	la	a4, test+8192
	li	a3, 0xa55a
loop:
	sw	a3, (a2)	
	li	s1, 0
	sw	s1, (a4)
	lw	a0, (a2)
	sub	a0, a3
	bnez	a0, f1
		li	a0, 'O'
		j	f2
f1:		li	a0, 'B'
f2:	jal	send
	j	loop


test:	.word 0


end:
