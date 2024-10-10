all:	vcasm  ld

vcasm:	main.c vc.tab.c
	gcc -o vcasm main.c -g

vc.tab.c: vc.y
	bison vc.y -k

test:	vcasm test.s
	./vcasm -s -m -o ../test/init.v test.s

init.bin:	vcasm init.s
	./vcasm -b -m -o init.bin init.s

boot.bin:	vcasm boot.s
	./vcasm -b -m -o boot.bin boot.s

start.bin:	vcasm start.s
	./vcasm -b -m -o start.bin start.s

ld:	ld.c	
	gcc -I /home/paul/tt06/vc32/bsd/usr/include -I /home/paul/tt06/vc32/bsd/usr//sys -I /home/paul/tt06/vc32/bsd/usr//sys/h  -o ld ld.c -g

