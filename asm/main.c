#include <stdio.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <unistd.h>

#define _AOUT_INCLUDE_

struct	exec {
	int	      a_magic;	    /* magic number */
	unsigned int  a_text;	    /* size of text segment */
	unsigned int  a_data;	    /* size of initialized data	*/
	unsigned int  a_bss;	    /* size of uninitialized data */
	unsigned int  a_syms;	    /* size of symbol table */
	unsigned int  a_entry;	    /* entry point */
	unsigned int  a_unused;	    /* not used	*/
	unsigned int  a_flag;	    /* relocation info stripped	*/
};


#define	NOVL	      15	    /* number of overlays */
struct	ovlhdr {
	int	      max_ovl;	    /* maximum overlay size */
	unsigned int  ov_siz[NOVL]; /* size of i'th overlay */
};

struct	xexec {
	struct exec e;
	struct ovlhdr o;
};

#define	A_MAGIC1      0407	    /* normal */
#define	A_MAGIC2      0410	    /* read-only text */
#define	A_MAGIC3      0411	    /* separated I&D */
#define	A_MAGIC4      0405	    /* overlay */
#define	A_MAGIC5      0430	    /* auto-overlay (nonseparate) */
#define	A_MAGIC6      0431	    /* auto-overlay (separate) */

struct	nlist {
#ifdef	_AOUT_INCLUDE_
	union {
	      char *n_name;/* In memory	address	of symbol name */
	      off_t n_strx;/* String table offset (file) */
	} n_un;
#else
	char	      *n_name;	 /* symbol name	(in memory) */
#endif
	u_char	      n_type;	 /* Type of symbol - see below */
	char	      n_ovly;	 /* Overlay number */
	u_int	      n_value;	 /* Symbol value */
};

/*
 *	relocation data 1 word/word of text/data
 */

#define REL_ABS 	0
#define		REL_TEXT	0
#define		REL_DATA	1
#define 	REL_REL 	2
#define REL_BR 		4
#define REL_JMP 	5
#define REL_LUI 	6
#define REL_ADD 	10

/*
* Simple values	for n_type.
*/
#define	N_UNDF	      0x0	 /* undefined */
#define	N_ABS	      0x1	 /* absolute */
#define	N_TEXT	      0x2	 /* text symbol	*/
#define	N_DATA	      0x3	 /* data symbol	*/
#define	N_BSS	      0x4	 /* bss	symbol */
#define	N_REG	      0x14	 /* register name */
#define	N_FN	      0x1f	 /* file name symbol */

#define	N_EXT	      0x20	 /* external bit, or'ed	in */
#define	N_TYPE	      0x1f	 /* mask for all the type bits */

struct symbol {
	char *name;
	unsigned int offset;	
	unsigned int soffset;	// string table offset
	unsigned int toffset;	// symbol table offset
	int index;
	unsigned char type;	// N_ type
	unsigned char found;	// 0 unreferenced, 1 defined
	struct symbol *next;
};
int sym_index=0;
struct symbol *list=0;

struct reloc {
	int offset;
	int extra;
	int index;
	int line;
	int type;
	unsigned char seg;
	struct reloc *next;
};
int reloc_index=0;
struct reloc *reloc_first;
struct reloc *reloc_last;

struct num_label {
	unsigned char seg;
	unsigned int offset;
	unsigned int index;
	struct num_label *next;
};
struct num_label *num_first=0;
struct num_ref {
	unsigned char	seg;
	unsigned char	type;
	unsigned	offset;
	int		ind;
	int 		line;
	struct num_ref	*prev;
	struct num_ref	*next;
};
struct num_ref *num_ref_first=0;

#define YYDEBUG 1

unsigned short text[4096];
unsigned int text_size = 0;
unsigned short data[4096];
unsigned int data_size = 0;
unsigned int bss_size = 0;
unsigned char seg=0;
unsigned char aout=1;

int yyval;
int line=1;
int errs=0;
int bit32=0;
int sym_count;

void declare_label(int type, int ind);
void emit(unsigned int ins);
void emit_data(int word, unsigned int data);
void emit_space(unsigned int sz);
void set_seg(int seg);
void set_offset(int type, unsigned int offset);
unsigned ref_label(int ind, int type, int offset);
void set_extern(int ind);

int
shift_exp(int r) {
	if (!bit32) {
		if (r >= 1 && r <= 16)
			return ((r&0xc)<<1) | ((r&3)<<5);
		fprintf(stderr, "%d: shift must be between 1 and 16 - %d\n", line, r);
	} else {
		if (r >= 1 && r <= 32)
			return ((r&0xc)<<1) | ((r&7)<<5);
		fprintf(stderr, "%d: shift must be between 1 and 32 - %d\n", line, r);
	}
	errs++;
	return 0;
}


int
check_inv(int r) {
	if (r>=1 &&r <= 15)
		return r<<2;
	errs++;
	fprintf(stderr, "%d: invalid mmu flush %d (must be 1-15)\n", line, r);
	return 0;
}
void
chkr(int r) {
	if (r&8)
		return;
	errs++;
	fprintf(stderr, "%d: invalid register\n", line);
	
}

int imm6(int v)
{
	if (v < 0 || v >= (1<<6)) {
		errs++;
		fprintf(stderr, "%d: invalid constant (must be >=0 <64)\n", line);
	}
	return(((v&0x3)<<5) | (((v>>2)&3)<<3) |(((v>>4)&1)<<12) | (((v>>5)&1)<<2));
}

int imm8(int v, int l)
{
	if (!bit32 && v&0x8000)
		v |= 0xffff0000;
	if (v < -(1<<7) || v >= (1<<7)) {
		errs++;
		fprintf(stderr, "%d: invalid constant (must be >=-128 <128)\n", (l?l:line));
	}
	return(((v&0x3)<<5) | (((v>>2)&7)<<10)| (((v>>5)&7)<<2));
}

int roffX(int v)
{
	if (bit32?v&3:v&1) {
		errs++;
		fprintf(stderr, "%d: invalid offset (must be word aligned)\n", line);
		return 0;
	}
	if (bit32) {
		if (v < 0 || v >= (1<<7)) {
			errs++;
			fprintf(stderr, "%d: invalid offset (must be >=0 <128)\n", line);
			return 0;
		}
		return ( (((v>>6)&1)<<5) |  (((v>>2)&1)<<6) | (((v>>3)&7)<<10));
	} else {
		if (v < 0 || v >= (1<<6)) {
			errs++;
			fprintf(stderr, "%d: invalid offset (must be >=0 <64)\n", line);
			return 0;
		}
		return ( (((v>>5)&1)<<5)  | (((v>>1)&1)<<6) | (((v>>2)&7)<<10));
	}	
}

int roffIO(int v)
{
	if (v&1) {
		errs++;
		fprintf(stderr, "%d: invalid offset (must be word aligned)\n", line);
		return 0;
	}
	if (v < 0 || v >= (1<<4)) {
		errs++;
		fprintf(stderr, "%d: invalid offset (must be >=0 <16)\n", line);
		return 0;
	}
	return ( (((v>>1)&1)<<6) | (((v>>2)&3)<<10));
}

int roff(int v)
{
	if (v < 0 || v >= (1<<5)) {
		errs++;
		fprintf(stderr, "%d: invalid offset (must be >=0 <32)\n", line);
		return 0;
	}
	if (bit32) {
		return ( ((v&1)<<5)  | (((v>>1)&1)<<12) | (((v>>2)&1)<<6) | (((v>>3)&3)<<10));
	} else {
		return ( ((v&1)<<5)  | (((v>>1)&1)<<6) | (((v>>2)&7)<<10));
	}	
}

int offX(int v)
{
	if (bit32?v&3:v&1) {
		errs++;
		fprintf(stderr, "%d: invalid offset (must be word aligned)\n", line);
		return 0;
	}
	if (bit32) {
		if (v < 0 || v >= (1<<9)) {
			errs++;
			fprintf(stderr, "%d: invalid offset (must be >=0 <512)\n", line);
			return 0;
		}
		v >>= 2;
	} else {
		if (v < 0 || v >= (1<<8)) {
			errs++;
			fprintf(stderr, "%d: invalid offset (must be >=0 <256)\n", line);
			return 0;
		}
		v >>= 1;
	}	
	return ( ((v&1)<<6)  | (((v>>1)&1)<<5) | (((v>>2)&3)<<11|(((v>>4)&7)<<2)));
}

int off(int v)
{
	if (v < 0 || v >= (1<<7)) {
		errs++;
		fprintf(stderr, "%d: invalid offset (must be >=0 <128)\n", line);
		return 0;
	}
	if (bit32) {
		return ( ((v&1)<<4)  | (((v>>1)&1)<<6)  | (((v>>2)&1)<<5) | (((v>>3)&3)<<11|(((v>>5)&3)<<2)));
	} else {
		return ( ((v&1)<<11)  | (((v>>1)&7)<<4)|(((v>>4)&1)<<12)|(((v>>5)&3)<<2));
	}	
}

int zoffX(int v)
{
	if (bit32?v&3:v&1) {
		errs++;
		fprintf(stderr, "%d: invalid offset (must be word aligned)\n", line);
		return 0;
	}
	if (bit32) {
		if (v < 0 || v >= (1<<9)) {
			errs++;
			fprintf(stderr, "%d: invalid offset (must be >=0 <512)\n", line);
			return 0;
		}
		v >>= 2;
	} else {
		if (v < 0 || v >= (1<<8)) {
			errs++;
			fprintf(stderr, "%d: invalid offset (must be >=0 <256)\n", line);
			return 0;
		}
		v >>= 1;
	}	
	return ( ((v&1)<<6)  |  (((v>>1)&7)<<10)|(((v>>4)&1)<<5)|(((v>>5)&7)<<7));
}

int addsp(int v)
{
	if (bit32?v&3:v&1) {
		errs++;
		fprintf(stderr, "%d: invalid offset (must be word aligned)\n", line);
		return 0;
	}
	if (bit32) {
		if (v < -(1<<8) || v >= (1<<8)) {
			errs++;
			fprintf(stderr, "%d: invalid offset (must be >=-256 <256)\n", line);
			return 0;
		}
		v >>= 2;
	} else {
		if (v < -(1<<7) || v >= (1<<7)) {
			errs++;
			fprintf(stderr, "%d: invalid offset (must be >=-128 <128)\n", line);
			return 0;
		}
		v >>= 1;
	}	
	return ( ((v&1)<<6)  | (((v>>1)&1)<<5) | (((v>>2)&3)<<11)|(((v>>4)&7)<<2) );
}

int luioff(int v, int l)
{
	if (v&0xff || v&~0xffff) {
		errs++;
		fprintf(stderr, "%d: invalid constant (must be 256 byte aligned and 16 bits)\n", l?l:line);
		return 0;
	}
	v>>=8;

	if (((v>>7)&1) != ((v>>6)&1)) {
		return 2|(((v&0x1f)<<2)| (((v>>5)&1)<<12) | (((v>>6)&1)<<11));
	}
	return (((v&0x1f)<<2)| (((v>>5)&1)<<12) | (((v>>6)&1)<<11));
}

int simple_li(int v)
{
	if (!bit32 && v&0x8000)
		v |= 0xffff0000;
	if (v < -(1<<7) || v >= (1<<7) ) 
		return 0;
	return 1;
}

int lioff(int v)
{
	if (!bit32 && v&0x8000)
		v |= 0xffff0000;
	if (v < -(1<<7) || v >= (1<<7) ) {
		errs++;
		fprintf(stderr, "%d: invalid constant (must be signed 7 bits)\n", line);
		return 0;
	}
	return(((v&0x3)<<5) | (((v>>2)&7)<<10)| (((v>>5)&7)<<2));
}

int yylex(void);
void yyerror(char *err);

#include "vc.tab.c"

struct tab {char *name; int token; };

struct tab reserved[] = {
	"a0", t_a0,
	"a1", t_a1,
	"a2", t_a2,
	"a3", t_a3,
	"a4", t_a4,
	"a5", t_a5,
	"add", t_add,
	"addb", t_addb,
	"addbu", t_addbu,
	"addpc", t_addpc,
	"and", t_and,
	"beqz", t_beqz,
	"bgez", t_bgez,
	"bltz", t_bltz,
	"bnez", t_bnez,
	"bss", t_bss,
	"byte", t_byte,
	"csr", t_csr,
	"data", t_data,
	"dcache", t_dcache,
	"div", t_div,
	"ebreak", t_ebreak,
	"epc", t_epc,
	"extern", t_extern,
	"flush", t_flush,
	"icache", t_icache,
	"inv", t_inv,
	"invmmu", t_invmmu,
	"j", t_j,
	"jal", t_jal,
	"jalr", t_jalr,
	"jr", t_jr,
 	"la", t_la,
	"lb", t_lb,
	"ldio", t_ldio,
	"lea", t_lea,
	"li", t_li,
 	"lr", t_lr,
	"lui", t_lui,
	"lw", t_lw,
	"mmu", t_mmu,
	"mov", t_mv,
	"mul", t_mul,
	"mulhi", t_mulhi,
	"mv", t_mv,
	"nop", t_nop,
	"or", t_or,
	"ret", t_ret,
	"s0", t_s0,
	"s1", t_s1,
	"sb", t_sb,
	"sext", t_sext,
	"sll", t_sll,
	"sp", t_sp,
	"space", t_space,
	"sra", t_sra,
	"srl", t_srl,
	"stio", t_stio,
	"stmp", t_stmp,
	"sub", t_sub,
	"sw", t_sw,
	"swap", t_swap,
	"swapsp", t_swapsp,
	"syscall", t_syscall,
	"text", t_text,
	"word", t_word,
	"xor", t_xor,
	"zext", t_zext,
	0, 0
};


void
declare_label(int type, int ind)
{

	if (type) {
		struct num_label *sp;
		struct num_ref *rp, *trp;
		for (sp = num_first; sp; sp = sp->next) 
		if (sp->index == ind) {
use:
			sp->offset = (seg?data_size:text_size);
			sp->seg = seg;
			for (rp = num_ref_first; rp;) {
				if (rp->seg == seg && rp->ind == ind) {
					unsigned offset;
					int delta;
					unsigned short *cp;
					if (seg != rp->seg) {
						errs++;
						fprintf(stderr, "%d: '%df' jmp to another segment\n", rp->line, ind);
					} else {
						switch (seg) {
						case 0:	offset = text_size;
							cp = text;
							break;
						case 1: offset = data_size;
							cp = data;
						case 2:	;
						}
						delta = offset-rp->offset;
						if (rp->type == 6) {
							if (delta < -(1<<10) || delta >= (1<<10)) {
								errs++;
								fprintf(stderr, "%d: '%df' jmp too far\n", rp->line, ind);
							} else {
								cp[rp->offset>>1] |=  (((delta>>1)&7)<<3) | (((delta>>4)&1)<<11) | (((delta>>5)&1)<<2) | (((delta>>6)&1)<<7) | (((delta>>7)&1)<<6) | (((delta>>8)&3)<<9)| (((delta>>10)&1)<<8) | (((delta>>11)&1)<<12);
							}
						} else {
							if (delta < -(1<<6) || delta >= (1<<6)) {
								errs++;
								fprintf(stderr, "%d: '%df' branch too far\n", rp->line, ind);
							} else {
								cp[rp->offset>>1] |= (((delta>>1)&3)<<3) | (((delta>>3)&3)<<10) | (((delta>>5)&1)<<2) | (((delta>>6)&3)<<5) | (((delta>>8)&1)<<12);
							}
						}
					}
					trp = rp;
					rp = rp->next;
					if (rp)
						rp->prev = trp->prev;
					if (trp->prev) {
						trp->prev->next = rp;
					} else {
						num_ref_first = rp;
					}
					free(trp);
				} else {
					rp = rp->next;
				}
			}
			return;
		} 
		sp = malloc(sizeof(*sp));
		assert(sp);
		sp->next = num_first;
		sp->index = ind;
		num_first =sp;
		goto use;
	} else {
		struct symbol *sp;
		for (sp = list; sp; sp = sp->next) 
		if (sp->index == ind) {
			if (sp->found) {
				errs++;
				fprintf(stderr, "%d: label '%s' declared twice\n", line, sp->name);
			}
			sp->type &= ~N_TYPE;
			switch (seg) {
			case 0: sp->type |= N_TEXT; sp->offset = text_size; break;
			case 1: sp->type |= N_DATA; sp->offset = data_size; break;
			case 2: sp->type |= N_BSS; sp->offset = bss_size; break;
			}
			sp->found = 1;
			return;
		}
	}
	assert(1);
}

void
set_extern(int ind)
{
	struct symbol *sp;
	for (sp = list; sp; sp = sp->next) 
	if (sp->index == ind) {
		sp->type |= N_EXT;
		return;
	}
	assert(1);
}


unsigned
ref_label(int ind, int type, int offset)
{
	struct reloc *rp;
	if (type == 6 || type == 7) {
		if (ind < 0) {
			struct num_label *np;
			ind = -ind;
			for (np = num_first; np; np = np->next)
			if (ind == np->index) {
				unsigned offset = (seg?data_size:text_size);
				int delta;
				if (np->seg != seg) {
					errs++;
					fprintf(stderr, "%d: '%db' jmp to another segment not allowed\n", line, ind);
					return 0;
				} else
				delta = np->offset-offset;
				if (type == 6) {
					if (delta < -(1<<10) || delta >= (1<<10)) {
						errs++;
						fprintf(stderr, "%d: '%db' jmp too far\n", line, ind);
						return 0;
					} else {
						return  (((delta>>1)&7)<<3) | (((delta>>4)&1)<<11) | (((delta>>5)&1)<<2) | (((delta>>6)&1)<<7) | (((delta>>7)&1)<<6) | (((delta>>8)&3)<<9)| (((delta>>10)&1)<<8) | (((delta>>11)&1)<<12);
					}
				} else {
					if (delta < -(1<<6) || delta >= (1<<6)) {
						errs++;
						fprintf(stderr, "%d: '%db' branch too far\n", line, ind);
						return 0;
					} else {
						return  (((delta>>1)&3)<<3) | (((delta>>3)&3)<<10) | (((delta>>5)&1)<<2) | (((delta>>6)&3)<<5) | (((delta>>8)&1)<<12);
					}
				}
			}
			fprintf(stderr, "%d: backwards reference %db not found;\n", line, ind);
			errs++;
		} else {
			struct num_ref *rp;
			rp = malloc(sizeof(*rp));
			assert(rp);
			rp->ind = ind;
			rp->type = type;
			rp->line = line;
			rp->seg = seg;
			rp->offset = (seg?data_size:text_size);
			if (num_ref_first)
				num_ref_first->prev = rp;
			rp->prev = 0;
			rp->next = num_ref_first;
			num_ref_first = rp;
		}
		return 0;
	}
	rp = malloc(sizeof(*rp));
	switch (seg) {
	case 0: rp->offset = text_size; break;
	case 1: rp->offset = data_size; break;
	}
	rp->seg = seg;
	rp->extra = offset;
	rp->index = ind;
	rp->line = line-1;
	rp->type = type;
	rp->next = 0;
	if (reloc_last) {
		reloc_last->next = rp;
		reloc_last = rp;
	} else {
		reloc_first = rp;
		reloc_last = rp;
	}
	return 0;
}

static unsigned char text_over=0;
static unsigned char data_over=0;

void
set_seg(int s)
{
	if (s && !aout) {
		fprintf(stderr, "%d: can only change segments for a.out format files\n", line-1);
		errs++;
		return;
	}
	seg = s;
}

void
emit_space(unsigned int sz)
{
	switch (seg) {
	case 0:	if ((text_size+sz) >= (sizeof(text))) {
			if (!text_over) {
				fprintf(stderr, "%d: ran out of code space\n", line-1);
				errs++;
				text_over = 1;
			}
			return;
		}
		text_size += sz;
		break;
	case 1:	if ((data_size+sz) >= (sizeof(data))) {
			if (!data_over) {
				fprintf(stderr, "%d: ran out of code space\n", line-1);
				errs++;
				data_over = 1;
			}
			return;
		}
		data_size += sz;
		break;
	case 2:	bss_size += sz;
		break;
	}
}

void
emit_data(int word, unsigned int datav)
{
	switch (seg) {
	case 0:	if (word && text_size&1)
			text_size++;
		if (text_size >= (sizeof(text))) {
			if (!text_over) {
				fprintf(stderr, "%d: ran out of code space\n", line-1);
				errs++;
				text_over = 1;
			}
			return;
		}
		if (word) {
			text[text_size>>1] = datav;
			text_size += 2;
		} else {
			if (text_size&1) {
				text[text_size>>1] = datav&0xff;
			} else {
				text[text_size>>1] |= (datav&0xff)<<8;
			}
			text_size++;
		}
		break;
	case 1:	if (word && data_size&1)
			data_size++;
		if (data_size >= (sizeof(data))) {
			if (!data_over) {
				fprintf(stderr, "%d: ran out of data space\n", line-1);
				errs++;
				data_over = 1;
			}
			return;
		}
		if (word) {
			data[data_size>>1] = datav;
			data_size += 2;
		} else {
			if (data_size&1) {
				data[data_size>>1] = datav&0xff;
			} else {
				data[data_size>>1] |= (datav&0xff)<<8;
			}
			data_size++;
		}
		break;
	default:fprintf(stderr, "%d: non-0 data writted to bss\n", line-1);
		errs++;
		break;
	}
}

void
emit(unsigned int ins)
{
	switch (seg) {
	case 0:	if (text_size >= (sizeof(text))) {
			if (!text_over) {
				fprintf(stderr, "%d: ran out of code space\n", line-1);
				errs++;
				text_over = 1;
			}
			return;
		}
		text[text_size>>1] = ins;
		text_size += 2;
		break;
	case 1:	if (data_size >= (sizeof(data))) {
			if (!data_over) {
				fprintf(stderr, "%d: ran out of data space\n", line-1);
				errs++;
				data_over = 1;
			}
			return;
		}
		data[data_size>>1] = ins;
		data_size += 2;
		break;
	default:fprintf(stderr, "%d: non-0 data writted to bss\n", line-1);
		errs++;
		break;
	}
}

void
set_offset(int type, unsigned int offset)
{
	switch (seg) {
	case 0: if (type) {
			text_size += offset;
		} else {
			text_size = offset;
		}
		break;
	case 1: if (type) {
			data_size += offset;
		} else {
			data_size = offset;
		}
		break;
	case 2: if (type) {
			bss_size += offset;
		} else {
			bss_size = offset;
		}
		break;
	}
}

FILE *fin;
int eof=0;

void
yyerror(char *err)
{
	errs++;
	fprintf(stderr, "%d: %s\n", line, err);
}

int
yylex(void)
{
	int c;

	if (eof)
		return 0;
	c = fgetc(fin);
	while (c == ' ' || c == '\t')
		c = fgetc(fin);
	if (c == EOF) {
		eof = 1;
		line++;
		return t_nl;
	} else
	if (c == '/') {
		c = fgetc(fin);
		if (c != '/') {
			ungetc(c, fin);
			return c;
		}
		for (;;) {
			c = fgetc(fin);
			if (c == EOF || c == '\n')
				break;
		}
		line++;
		return t_nl;
	} else
	if (c == '#') {
		for (;;) {
			c = fgetc(fin);
			if (c == EOF || c == '\n')
				break;
		}
		line++;
		return t_nl;
	} else
	if (c == '\n') {
		line++;
		return t_nl;
	} else
	if (c == '\'') {
		c = fgetc(fin);
		if (c == '\\') {
			c = fgetc(fin);
			switch (c) {
			case 'n': c = '\n'; break;
			case 'r': c = '\r'; break;
			case 't': c = '\t'; break;
			case '\'': c = '\''; break;
			case '\\': c = '\\'; break;
			default:;
			}
		}
		yylval = c;
		c = fgetc(fin);
		if (c != '\'') {
			yyerror("closing ' expected");
		}
		return t_value;
	} else
	if (c >= '0' && c <= '9') {
		int ind;
		char v[100];
		char c1;
		c1 = c;
		ind = 0;
		v[ind++] = c;
		c = fgetc(fin);
		if (c1 == '0' && (c == 'x' || c == 'X')) {
			v[ind++] = c;
			c = fgetc(fin);
			while (isxdigit(c)) {
				if (ind < (sizeof(v)-1))
					v[ind++] = c; 
				c = fgetc(fin);
			}
			v[ind] = 0;
			ungetc(c, fin);
			yylval = strtol(v, NULL, 16);
		} else
		if (c1 == '0') {
			while (c >= '0' && c <= '7') {
				if (ind < (sizeof(v)-1))
					v[ind++] = c; 
				c = fgetc(fin);
			}
			v[ind] = 0;
			ungetc(c, fin);
			yylval = strtol(v, NULL, 8);
		} else {
			while (isdigit(c)) {
				if (ind < (sizeof(v)-1))
					v[ind++] = c; 
				c = fgetc(fin);
			}
			v[ind] = 0;
			if (c == 'f' || c == 'b') {
				yylval = (c=='f'?1:-1)*strtol(v, NULL, 0);
				return t_num_label;
			}
			ungetc(c, fin);
			yylval = strtol(v, NULL, 0);
		}
		return t_value;
	} else
	if ((c >= 'a' && c <= 'z') ||
	    (c >= 'A' && c <= 'Z') || c == '_') {		
		int i;
		int ind=0;
		char v[33];
		struct symbol *sp;

		while ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
            	       (c >= 'A' && c <= 'Z') || c == '_' ) {
			if (ind < (sizeof(v)-1))
				v[ind++] = c; 
			c = fgetc(fin);
		}
		ungetc(c, fin);
		v[ind] = 0;
		for (i = 0; reserved[i].name; i++) {
			int cmp = strcmp(v, reserved[i].name);
			if (cmp == 0)
				return reserved[i].token;
			if (cmp < 0)
				break;
		}
		for (sp = list; sp; sp=sp->next)
		if (strcmp(v, sp->name) == 0) {
			yylval = sp->index;
			return t_name;
		}
		sp = malloc(sizeof(*sp));
		sp->index = sym_index++;
		sp->found = 0;
		sp->name = strdup(v);
		sp->next = list;
		sp->type = N_UNDF;
		list = sp;
		yylval = sp->index;
		sym_count++;
		return t_name;
	} else {
		if (c == '<') {
			c = fgetc(fin);
			if (c == '<')
				return t_shl;
			ungetc(c, fin);
			c = '<';
		} else
		if (c == '>') {
			c = fgetc(fin);
			if (c == '>')
				return t_shr;
			ungetc(c, fin);
			c = '>';
		}
		if (c == '/') {
			c = fgetc(fin);
			if (c == '/') {		
				while (c != '\n' && c != EOF)
					c = fgetc(fin);
				return t_nl;
			}
			ungetc(c, fin);
			c = '/';
		}
		return c;
	}
}

int
main(int argc, char **argv)
{
	int i, bin_out=0,hex_out=0,src_out=0,dump_symbols=0;
	struct reloc *rp;
	struct num_ref *np;
	char *in_name = 0;
	char *out_name = "a.out";

	yydebug = 0;
	for (i = 1; i < argc; i++) {	
		if (strcmp(argv[i], "-y") == 0) {
			yydebug = 1;
		} else
		if (strcmp(argv[i], "-m") == 0) {
			dump_symbols = 1;
		} else
		if (strcmp(argv[i], "-h") == 0) {
			hex_out = 1;
			aout=0;
		} else
		if (strcmp(argv[i], "-s") == 0) {
			src_out = 1;
			aout=0;
		} else
		if (strcmp(argv[i], "-b") == 0) {
			bin_out = 1;
			aout=0;
		} else
		if (strcmp(argv[i], "-32") == 0) {
			bit32 = 1;
		} else
		if (strcmp(argv[i], "-o") == 0 && i != (argc-1)) {
			i++;
			out_name = argv[i];
		} else {
			if (in_name) {
				fprintf(stderr, "too many inout files\n");
				errs++;
			}
			in_name = argv[i];
		}
	}

	if (!in_name) {
		fprintf(stderr, "No file specified\n");
		return 1;
	}
	fin = fopen(in_name, "r");
	if (!fin) {
		fprintf(stderr, "Can't open '%s'\n", in_name);
		return 1;
	}
	if (yyparse()) {
		//fprintf(stderr, "%d: syntax error\n", line);
		return 1;
	}
	if (text_size&1)
		text_size++;
	if (data_size&1)
		data_size++;
	if (bss_size&1)
		bss_size++;
	for (np = num_ref_first; np; np = np->next) {
		errs++;
		fprintf(stderr, "%d: '%df' not defined\n", np->line, np->ind);
	}
	if (!aout)
	for (rp = reloc_first; rp; rp = rp->next) {
		struct symbol *sp;
		int found = 0;
		for (sp = list; sp; sp=sp->next) 
		if (rp->index == sp->index) {
			int v, delta;
			found = 1;
			if (!sp->found) {
				errs++;
				fprintf(stderr, "%d: '%s' not defined\n", rp->line, sp->name);
			} else
			switch (rp->type) {
			case 1: text[rp->offset>>1] += sp->offset;
				break;
			case 2:	// jmp
				delta = sp->offset-rp->offset;
				if (delta < -(1<<10) || delta >= (1<<10)) {
					errs++;
					fprintf(stderr, "%d: '%s' jmp too far\n", rp->line, sp->name);
				} else {
					v = (((delta>>1)&7)<<3) | (((delta>>4)&1)<<11) | (((delta>>5)&1)<<2) | (((delta>>6)&1)<<7) | (((delta>>7)&1)<<6) | (((delta>>8)&3)<<9)| (((delta>>10)&1)<<8) | (((delta>>11)&1)<<12);
//printf("reloc[%d] delta=0x%d v=0x%x line=%d '%s'\n", rp->offset, delta, v, rp->line, sp->name);
					text[rp->offset>>1] |= v;
				}
				break;
			case 3:	// branch
				delta = sp->offset-rp->offset;
				if (delta < -(1<<6) || delta >= (1<<6)) {
					errs++;
					fprintf(stderr, "%d: '%s' branch too far\n", rp->line, sp->name);
				} else {
					v = (((delta>>1)&3)<<3) | (((delta>>3)&3)<<10) | (((delta>>5)&1)<<2) | (((delta>>6)&3)<<5) | (((delta>>8)&1)<<12);
					text[rp->offset>>1] |= v;
				}
				break;
			case 4:	// la lui part
				delta = sp->offset+rp->extra;
				if (delta >= (1<<15)) {
					errs++;
					fprintf(stderr, "%d: '%s' la too far\n", rp->line, sp->name);
				} else {
					if (delta&0x80) {
						delta = (delta&~0xff)+0x100;
					} else {
						delta = delta&~0xff;
					}
					text[rp->offset>>1] |= luioff(delta, rp->line);
				}
				break;
			case 5:	// la add part
				delta = (sp->offset+rp->extra)&0xff;
				if (delta&0x80) 
					delta = -(0x100-delta);
				text[rp->offset>>1] |= imm8(delta, rp->line);
				break;
			}
		}

		assert(found);
	}
	if (!errs) {
		if (hex_out) {
			FILE *fout = fopen(out_name, "w");
			if (fout) {
				for (i = 0; i < text_size; i+=2) {
					fprintf(fout, "%02x ", text[i>>1]&0xff);
					fprintf(fout, "%02x\n", (text[i>>1]>>8)&0xff);	
				}
				fclose(fout);
			} else {
				fprintf(stderr, "Can't open output file '%s'\n", out_name);
				errs++;
			}
		} else
		if (src_out) {
			FILE *fout = fopen(out_name, "w");
			if (fout) {
				for (i = 0; i < text_size; i+=2) {
					fprintf(fout, "	m[16'h%02x] = 8'h%02x;\n", i, text[i>>1]&0xff);
					fprintf(fout, "	m[16'h%02x] = 8'h%02x;\n", i+1, (text[i>>1]>>8)&0xff);	
				}
				fclose(fout);
			} else {
				fprintf(stderr, "Can't open output file '%s'\n", out_name);
				errs++;
			}
		} else
		if (bin_out) {
			FILE *fout = fopen(out_name, "wb");
			if (fout) {
				fwrite(text, 1, text_size, fout);	
				fclose(fout);
			} else {
				fprintf(stderr, "Can't open output file '%s'\n", out_name);
				errs++;
			}
		} else 
		if (aout) {
			FILE *fout = fopen(out_name, "wb");
			if (fout) {
#ifdef NOTDEF
#define REL_ABS 	0
#define		REL_TEXT	0
#define		REL_DATA	1
#define 	REL_REL 	2
#define REL_BR 		4
#define REL_JMP 	5
#define REL_LUI 	6
#define REL_ADD 	10
struct	exec {
		int	      a_magic;	    /* magic number */
		unsigned int  a_text;	    /* size of text segment */
		unsigned int  a_data;	    /* size of initialized data	*/
		unsigned int  a_bss;	    /* size of uninitialized data */
		unsigned int  a_syms;	    /* size of symbol table */
		unsigned int  a_entry;	    /* entry point */
		unsigned int  a_unused;	    /* not used	*/
		unsigned int  a_flag;	    /* relocation info stripped	*/
}
struct	nlist {
#ifdef	_AOUT_INCLUDE_
	union {
	      char *n_name;/* In memory	address	of symbol name */
	      off_t n_strx;/* String table offset (file) */
	} n_un;
#else
	char	      *n_name;	 /* symbol name	(in memory) */
#endif
	u_char	      n_type;	 /* Type of symbol - see below */
	char	      n_ovly;	 /* Overlay number */
	u_int	      n_value;	 /* Symbol value */
};
#endif
				struct exec e;
				struct nlist n;
				struct symbol *sp;
				int string_offset;

				for (sp=list, i = 1; i <= sym_count; i++, sp=sp->next) 
					sp->toffset = i;
				e.a_magic = 0;
				e.a_text = text_size;
				e.a_data = data_size;
				e.a_bss = bss_size;
				e.a_syms = sym_count+1;
				e.a_entry = 0;
				e.a_unused = 0;
				e.a_flag = reloc_first?0:1;
				if (fwrite(&e, sizeof(e), 1, fout) != 1) {
outerr:
					fprintf(stderr, "Error writing file '%s'\n", out_name);
					fclose(fout);
					unlink(out_name);
					exit(1);
				}
				if (text_size && fwrite(text, text_size, 1, fout) != 1) goto outerr;
				
				if (data_size && fwrite(data, data_size, 1, fout) != 1) goto outerr;
				if (reloc_first) {
					struct reloc *rp = reloc_first;
					unsigned short s;
					for (i = 0; i < text_size; i+=2) {	// text reloc
						while (rp && rp->seg !=0)
							rp = rp->next;
						s = 0;
						if (rp && rp->offset == i) {
							for (sp = list; sp; sp=sp->next) 
							if (rp->index == sp->index) {
								switch (rp->type) {
								case 1: s = sp->toffset|REL_ABS;
									break;
								case 2:	s = sp->toffset|REL_JMP;
									break;
								case 3:	s = sp->toffset|REL_BR;
									break;
								case 4:	// la lui part
									s = sp->toffset|REL_LUI;
									break;
								case 5:	// la add part
									s = sp->toffset|REL_ADD;
									break;
								}
							}
							rp = rp->next;
						}
						if (fwrite(&s, 2, 1, fout) != 1) goto outerr;
					}
					rp = reloc_first;
					for (i = 0; i < data_size; i+=2) {	// data reloc
						while (rp && rp->seg !=1)
							rp = rp->next;
						s = 0;
						if (rp && rp->offset == i) {
							for (sp = list; sp; sp=sp->next) 
							if (rp->index == sp->index) {
								switch (rp->type) {
								case 1: s = sp->toffset|REL_ABS;
									break;
								case 2:	s = sp->toffset|REL_JMP;
									break;
								case 3:	s = sp->toffset|REL_BR;
									break;
								case 4:	// la lui part
									s = sp->toffset|REL_LUI;
									break;
								case 5:	// la add part
									s = sp->toffset|REL_ADD;
									break;
								}
							}
							rp = rp->next;
						}
						if (fwrite(&s, 2, 1, fout) != 1) goto outerr;
					}
				}	
				fflush(fout);
				fseek(fout, (sym_count+1)*sizeof(n), SEEK_CUR);
				string_offset = 0;
				i = strlen(in_name)+1;
				if (fwrite(in_name, i, 1, fout) != 1) goto outerr;
				string_offset += i;
				for (sp=list, i = 1; i <= sym_count; i++, sp=sp->next) {
					int l = strlen(sp->name)+1;
					sp->soffset = string_offset;
					string_offset += l;
					if (fwrite(sp->name, l, 1, fout) != 1) goto outerr;
				}
				fflush(fout);
				fseek(fout, -(sym_count+1)*sizeof(n), SEEK_CUR);
				
				n.n_un.n_strx = 0;	// file name
				n.n_type = N_FN;
				n.n_ovly = 0;
				n.n_value = 0;
				if (fwrite(&n, sizeof(n), 1, fout) != 1) goto outerr;
				for (sp=list, i = 1; i <= sym_count; i++, sp=sp->next) {
					n.n_un.n_strx = sp->soffset;
					if (sp->found) {
						n.n_type = sp->type;
					} else {
						n.n_type = N_UNDF|N_EXT;
					}
					n.n_ovly = 0;
					n.n_value = sp->offset;
					if (fwrite(&n, sizeof(n), 1, fout) != 1) goto outerr;
				}

				fflush(fout);
				rewind(fout);
				e.a_magic = A_MAGIC1;
				if (fwrite(&e, sizeof(e), 1, fout) != 1)  goto outerr;
				fclose(fout);
			} else {
				fprintf(stderr, "Can't open output file '%s'\n", out_name);
				errs++;
			}
		} else {
			fprintf(stderr, "no output\n");
			errs++;
		}
		if (dump_symbols) {
			struct symbol *sp;
			for (sp = list; sp; sp=sp->next) 
				fprintf(stderr, "'%s':	%04x\n", sp->name, sp->offset);
		}
	}
	return errs != 0?1:0;
}
