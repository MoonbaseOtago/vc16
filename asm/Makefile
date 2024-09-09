all:	vcasm  ld

vcasm:	main.c vc.tab.c
	gcc -o vcasm main.c -g

vc.tab.c: vc.y
	bison vc.y -k

test:	vcasm test.s
	./vcasm -s -m -o ../test/init.v test.s

ld:	ld.c	
	gcc -I /home/paul/tt06/vc32/bsd/usr/include -I /home/paul/tt06/vc32/bsd/usr//sys -I /home/paul/tt06/vc32/bsd/usr//sys/h  -o ld ld.c -g

