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


start:
	li	a5, 0x20	// 0x20 - uart base
	li	a0, 108		// 50000000/115200/4 
	stio	a0, 8(a5)
	srl	a0, 8
	stio	a0, 10(a5)
	li	a0, 'H'
	jal	send
	li	a0, 'e'
	jal	send
	li	a0, 'l'
	jal	send
	li	a0, 'l'
	jal	send
	li	a0, 'o'
	jal	send
	li	a0, ' '
	jal	send
	li	a0, 'W'
	jal	send
	li	a0, 'o'
	jal	send
	li	a0, 'r'
	jal	send
	li	a0, 'l'
	jal	send
	li	a0, 'd'
	jal	send
	li	a0, '\n'
	jal	send
	li	a0, '\r'
	jal	send
y:	j	y
