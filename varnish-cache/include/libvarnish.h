/*-
 * Copyright (c) 2006 Verdens Gang AS
 * Copyright (c) 2006-2008 Linpro AS
 * All rights reserved.
 *
 * Author: Poul-Henning Kamp <phk@phk.freebsd.dk>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * $Id$
 */

#include <errno.h>
#include <time.h>
#include <stdint.h>

#ifndef NULL
#define NULL ((void*)0)
#endif

/* from libvarnish/argv.c */
void FreeArgv(char **argv);
char **ParseArgv(const char *s, int comment);

/* from libvarnish/crc32.c */
uint32_t crc32(uint32_t crc, const void *p1, unsigned l);
uint32_t crc32_l(const void *p1, unsigned l);

/* from libvarnish/num.c */
const char *str2bytes(const char *p, uintmax_t *r, uintmax_t rel);

/* from libvarnish/time.c */
void TIM_format(double t, char *p);
time_t TIM_parse(const char *p);
double TIM_mono(void);
double TIM_real(void);

/* from libvarnish/vct.c */
#define VCT_SP    	(1<<0)
#define VCT_CRLF  	(1<<1)
#define VCT_LWS   	(VCT_CRLF | VCT_SP)
#define VCT_CTL   	(1<<2)
#define VCT_UALPHA	(1<<3)
#define VCT_LOALPHA	(1<<4)
#define VCT_DIGIT	(1<<5)
#define VCT_HEX		(1<<6)

extern unsigned char vct_typtab[256];

static inline int
vct_is(unsigned char x, unsigned char y)
{
 
        return (vct_typtab[x] & (y));
}

#define vct_issp(x) vct_is(x, VCT_SP)
#define vct_iscrlf(x) vct_is(x, VCT_CRLF)
#define vct_islws(x) vct_is(x, VCT_LWS)
#define vct_isctl(x) vct_is(x, VCT_CTL)

/* from libvarnish/version.c */
void varnish_version(const char *);

/* from libvarnish/vtmpfile.c */
int vtmpfile(char *);

/*
 * assert(), AN() and AZ() are static checks that should not happen.
 * xxxassert(), XXXAN() and XXXAZ() are markers for missing code.
 */

#ifdef WITHOUT_ASSERTS
#define assert(e)	((void)(e))
#else /* WITH_ASSERTS */
#define assert(e)							\
do { 									\
	if (!(e))							\
		lbv_assert(__func__, __FILE__, __LINE__, #e, errno);	\
} while (0)
#endif

#define xxxassert(e)							\
do { 									\
	if (!(e))							\
		lbv_xxxassert(__func__, __FILE__, __LINE__, #e, errno); \
} while (0)

void lbv_assert(const char *, const char *, int, const char *, int);
void lbv_xxxassert(const char *, const char *, int, const char *, int);

/* Assert zero return value */
#define AZ(foo)	do { assert((foo) == 0); } while (0)
#define AN(foo)	do { assert((foo) != 0); } while (0)
#define XXXAZ(foo)	do { xxxassert((foo) == 0); } while (0)
#define XXXAN(foo)	do { xxxassert((foo) != 0); } while (0)
