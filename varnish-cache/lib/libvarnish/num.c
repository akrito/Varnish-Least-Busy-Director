/*-
 * Copyright (c) 2008 Linpro AS
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
 *
 * Deal with numbers with data storage suffix scaling
 */

#include "config.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#include <libvarnish.h>

const char *
str2bytes(const char *p, uintmax_t *r, uintmax_t rel)
{
	double fval;
	char *end;

	fval = strtod(p, &end);
	if (end == p || !isfinite(fval))
		return ("Invalid number");

	if (*end == '\0') {
		*r = (uintmax_t)fval;
		return (NULL);
	}

	if (end[0] == '%' && end[1] == '\0') {
		if (rel == 0)
			return ("Absolute number required");
		fval *= rel / 100.0;
	} else {
		/* accept a space before the multiplier */
		if (end[0] == ' ' && end[1] != '\0')
			++end;

		switch (end[0]) {
		case 'k': case 'K':
			fval *= (uintmax_t)1 << 10;
			++end;
			break;
		case 'm': case 'M':
			fval *= (uintmax_t)1 << 20;
			++end;
			break;
		case 'g': case 'G':
			fval *= (uintmax_t)1 << 30;
			++end;
			break;
		case 't': case 'T':
			fval *= (uintmax_t)1 << 40;
			++end;
			break;
		case 'p': case 'P':
			fval *= (uintmax_t)1 << 50;
			++end;
			break;
		case 'e': case 'E':
			fval *= (uintmax_t)1 << 60;
			++end;
			break;
		}

		/* accept 'b' for 'bytes' */
		if (end[0] == 'b' || end[0] == 'B')
			++end;

		if (end[0] != '\0')
			return ("Invalid suffix");
	}

	/* intentionally not round(fval) to avoid need for -lm */
	*r = (uintmax_t)(fval + 0.5);
	return (NULL);
}

#ifdef NUM_C_TEST
#include <assert.h>
#include <err.h>
#include <stdio.h>
#include <string.h>

struct test_case {
	const char *str;
	uintmax_t rel;
	uintmax_t val;
} test_cases[] = {
	{ "1",			(uintmax_t)0,		(uintmax_t)1 },
	{ "1B",			(uintmax_t)0,		(uintmax_t)1<<0 },
	{ "1 B",		(uintmax_t)0,		(uintmax_t)1<<0 },
	{ "1.3B",		(uintmax_t)0,		(uintmax_t)1 },
	{ "1.7B",		(uintmax_t)0,		(uintmax_t)2 },

	{ "1024",		(uintmax_t)0,		(uintmax_t)1024 },
	{ "1k",			(uintmax_t)0,		(uintmax_t)1<<10 },
	{ "1kB",		(uintmax_t)0,		(uintmax_t)1<<10 },
	{ "1.3kB",		(uintmax_t)0,		(uintmax_t)1331 },
	{ "1.7kB",		(uintmax_t)0,		(uintmax_t)1741 },

	{ "1048576",		(uintmax_t)0,		(uintmax_t)1048576 },
	{ "1M",			(uintmax_t)0,		(uintmax_t)1<<20 },
	{ "1MB",		(uintmax_t)0,		(uintmax_t)1<<20 },
	{ "1.3MB",		(uintmax_t)0,		(uintmax_t)1363149 },
	{ "1.7MB",		(uintmax_t)0,		(uintmax_t)1782579 },

	{ "1073741824",		(uintmax_t)0,		(uintmax_t)1073741824 },
	{ "1G",			(uintmax_t)0,		(uintmax_t)1<<30 },
	{ "1GB",		(uintmax_t)0,		(uintmax_t)1<<30 },
	{ "1.3GB",		(uintmax_t)0,		(uintmax_t)1395864371 },
	{ "1.7GB",		(uintmax_t)0,		(uintmax_t)1825361101 },

	{ "1099511627776",	(uintmax_t)0,		(uintmax_t)1099511627776 },
	{ "1T",			(uintmax_t)0,		(uintmax_t)1<<40 },
	{ "1TB",		(uintmax_t)0,		(uintmax_t)1<<40 },
	{ "1.3TB",		(uintmax_t)0,		(uintmax_t)1429365116109 },
	{ "1.7TB",		(uintmax_t)0,		(uintmax_t)1869169767219 },

	{ "1%",			(uintmax_t)1024,	(uintmax_t)10 },
	{ "2%",			(uintmax_t)1024,	(uintmax_t)20 },
	{ "3%",			(uintmax_t)1024,	(uintmax_t)31 },
	/* TODO: add more */

	{ 0, 0, 0 },
};

int
main(int argc, char *argv[])
{
	struct test_case *tc;
	uintmax_t val;
	int ec;

	(void)argc;
	for (ec = 0, tc = test_cases; tc->str; ++tc) {
		str2bytes(tc->str, &val, tc->rel);
		if (val != tc->val) {
			printf("%s: str2bytes(\"%s\", %ju) %ju != %ju\n",
			    *argv, tc->str, tc->rel, val, tc->val);
			++ec;
		}
	}
	/* TODO: test invalid strings */
	if (!ec)
		printf("OK\n");
	return (ec > 0);
}
#endif
