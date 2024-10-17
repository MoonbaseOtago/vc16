#include <stdio.h>

main()
{
	fseek(stdin, 16, 1);
	for (;;) {
		unsigned char v[2];
		if (fread(&v[0], 2, 1, stdin) != 1)
			break;
		printf("%02x %02x\n", v[0], v[1]);
	}
	return 0;
}
