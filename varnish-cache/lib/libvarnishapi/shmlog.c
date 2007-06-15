/*-
 * Copyright (c) 2006 Verdens Gang AS
 * Copyright (c) 2006-2007 Linpro AS
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

#include <stdio.h>
#include <errno.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <regex.h>
#include <sys/mman.h>
#include <assert.h>

#include "shmlog.h"
#include "miniobj.h"
#include "varnishapi.h"

/* Parameters */
#define			SLEEP_USEC	(50*1000)
#define			TIMEOUT_USEC	(5*1000*1000)

#define NFD		(256 * 256)

struct VSL_data {
	unsigned		magic;
#define VSL_MAGIC		0x6e3bd69b

	struct shmloghead	*head;
	unsigned char		*logstart;
	unsigned char		*logend;
	unsigned char		*ptr;

	/* for -r option */
	FILE			*fi;
	unsigned char		rbuf[5 + 255 + 1];

	int			b_opt;
	int			c_opt;
	int			d_opt;

	unsigned		flags;
#define F_SEEN_IX		(1 << 0)
#define F_NON_BLOCKING		(1 << 1)

	unsigned char		map[NFD];
#define M_CLIENT		(1 << 0)
#define M_BACKEND		(1 << 1)
#define M_SUPPRESS		(1 << 2)
#define M_SELECT		(1 << 3)

	int			regflags;
	regex_t			*regincl;
	regex_t			*regexcl;
};

#ifndef MAP_HASSEMAPHORE
#define MAP_HASSEMAPHORE 0 /* XXX Linux */
#endif

static int vsl_fd;
static struct shmloghead *vsl_lh;

static int vsl_nextlog(struct VSL_data *vd, unsigned char **pp);

/*--------------------------------------------------------------------*/

const char *VSL_tags[256] = {
#define SLTM(foo)       [SLT_##foo] = #foo,
#include "shmlog_tags.h"
#undef SLTM
};

/*--------------------------------------------------------------------*/

static int
vsl_shmem_map(char* varnish_name)
{
	int i;
	struct shmloghead slh;
	char buf[BUFSIZ];

	if (vsl_lh != NULL)
		return (0);

	sprintf(buf, "/tmp/%s/%s", varnish_name, SHMLOG_FILENAME);

	vsl_fd = open(buf, O_RDONLY);
	if (vsl_fd < 0) {
		fprintf(stderr, "Cannot open %s: %s\n",
		    buf, strerror(errno));
		return (1);
	}
	i = read(vsl_fd, &slh, sizeof slh);
	if (i != sizeof slh) {
		fprintf(stderr, "Cannot read %s: %s\n",
		    buf, strerror(errno));
		return (1);
	}
	if (slh.magic != SHMLOGHEAD_MAGIC) {
		fprintf(stderr, "Wrong magic number in file %s\n",
		    buf);
		return (1);
	}

	vsl_lh = mmap(NULL, slh.size + sizeof slh,
	    PROT_READ, MAP_SHARED|MAP_HASSEMAPHORE, vsl_fd, 0);
	if (vsl_lh == MAP_FAILED) {
		fprintf(stderr, "Cannot mmap %s: %s\n",
		    buf, strerror(errno));
		return (1);
	}
	return (0);
}

/*--------------------------------------------------------------------*/

struct VSL_data *
VSL_New(void)
{
	struct VSL_data *vd;

	assert(VSL_S_CLIENT == M_CLIENT);
	assert(VSL_S_BACKEND == M_BACKEND);
	vd = calloc(sizeof *vd, 1);
	assert(vd != NULL);
	vd->regflags = REG_EXTENDED | REG_NOSUB;
	vd->magic = VSL_MAGIC;
	return (vd);
}

/*--------------------------------------------------------------------*/

void
VSL_Select(struct VSL_data *vd, unsigned tag)
{

	CHECK_OBJ_NOTNULL(vd, VSL_MAGIC);
	vd->map[tag] |= M_SELECT;
}

/*--------------------------------------------------------------------*/

int
VSL_OpenLog(struct VSL_data *vd, char *varnish_name)
{
	unsigned char *p;

	CHECK_OBJ_NOTNULL(vd, VSL_MAGIC);
	if (vd->fi != NULL)
		return (0);

	if (vsl_shmem_map(varnish_name))
		return (1);

	vd->head = vsl_lh;
	vd->logstart = (unsigned char *)vsl_lh + vsl_lh->start;
	vd->logend = vd->logstart + vsl_lh->size;
	vd->ptr = vd->logstart;

	if (!vd->d_opt && vd->fi == NULL) {
		for (p = vd->ptr; *p != SLT_ENDMARKER; )
			p += p[1] + 5;
		vd->ptr = p;
	}
	return (0);
}

/*--------------------------------------------------------------------*/

void
VSL_NonBlocking(struct VSL_data *vd, int nb)
{
	if (nb)
		vd->flags |= F_NON_BLOCKING;
	else
		vd->flags &= ~F_NON_BLOCKING;
}

/*--------------------------------------------------------------------*/

static int
vsl_nextlog(struct VSL_data *vd, unsigned char **pp)
{
	unsigned char *p;
	unsigned w;
	int i;

	CHECK_OBJ_NOTNULL(vd, VSL_MAGIC);
	if (vd->fi != NULL) {
		i = fread(vd->rbuf, 4, 1, vd->fi);
		if (i != 1)
			return (-1);
		i = fread(vd->rbuf + 4, vd->rbuf[1] + 1, 1, vd->fi);
		if (i != 1)
			return (-1);
		*pp = vd->rbuf;
		return (1);
	}

	p = vd->ptr;
	for (w = 0; w < TIMEOUT_USEC;) {
		if (*p == SLT_WRAPMARKER) {
			p = vd->logstart;
			continue;
		}
		if (*p == SLT_ENDMARKER) {
			if (vd->flags & F_NON_BLOCKING)
				return (-1);
			w += SLEEP_USEC;
			usleep(SLEEP_USEC);
			continue;
		}
		vd->ptr = p + p[1] + 5;
		*pp = p;
		return (1);
	}
	vd->ptr = p;
	return (0);
}

int
VSL_NextLog(struct VSL_data *vd, unsigned char **pp)
{
	unsigned char *p;
	regmatch_t rm;
	unsigned u;
	int i;

	CHECK_OBJ_NOTNULL(vd, VSL_MAGIC);
	while (1) {
		i = vsl_nextlog(vd, &p);
		if (i != 1)
			return (i);
		u = (p[2] << 8) | p[3];
		switch(p[0]) {
		case SLT_SessionOpen:
		case SLT_ReqStart:
			vd->map[u] |= M_CLIENT;
			vd->map[u] &= ~M_BACKEND;
			break;
		case SLT_BackendOpen:
		case SLT_BackendXID:
			vd->map[u] |= M_BACKEND;
			vd->map[u] &= ~M_CLIENT;
			break;
		default:
			break;
		}
		if (vd->map[p[0]] & M_SELECT) {
			*pp = p;
			return (1);
		}
		if (vd->map[p[0]] & M_SUPPRESS)
			continue;
		if (vd->b_opt && !(vd->map[u] & M_BACKEND))
			continue;
		if (vd->c_opt && !(vd->map[u] & M_CLIENT))
			continue;
		if (vd->regincl != NULL) {
			rm.rm_so = 0;
			rm.rm_eo = p[1];
			i = regexec(vd->regincl, (char *)p + 4, 1, &rm, 0);
			if (i == REG_NOMATCH)
				continue;
		}
		if (vd->regexcl != NULL) {
			rm.rm_so = 0;
			rm.rm_eo = p[1];
			i = regexec(vd->regexcl, (char *)p + 4, 1, &rm, 0);
			if (i != REG_NOMATCH)
				continue;
		}
		*pp = p;
		return (1);
	}
}

/*--------------------------------------------------------------------*/

int
VSL_Dispatch(struct VSL_data *vd, vsl_handler *func, void *priv)
{
	int i;
	unsigned u;
	unsigned char *p;

	CHECK_OBJ_NOTNULL(vd, VSL_MAGIC);
	while (1) {
		i = VSL_NextLog(vd, &p);
		if (i <= 0)
			return (i);
		u = (p[2] << 8) | p[3];
		if (func(priv,
		    p[0], u, p[1],
		    vd->map[u] & (VSL_S_CLIENT|VSL_S_BACKEND),
		    (char *)p + 4))
			return (1);
	}
}

/*--------------------------------------------------------------------*/

int
VSL_H_Print(void *priv, enum shmlogtag tag, unsigned fd, unsigned len, unsigned spec, const char *ptr)
{
	FILE *fo = priv;

	assert(fo != NULL);
	if (tag == SLT_Debug) {
		fprintf(fo, "%5d %-12s %c \"", fd, VSL_tags[tag],
		    ((spec & VSL_S_CLIENT) ? 'c' : (spec & VSL_S_BACKEND) ? 'b' : ' '));
		while (len-- > 0) {
			if (*ptr >= ' ' && *ptr <= '~')
				fprintf(fo, "%c", *ptr);
			else
				fprintf(fo, "%%%02x", *ptr);
			ptr++;
		}
		fprintf(fo, "\"\n");
		return (0);
	}
	fprintf(fo, "%5d %-12s %c %.*s\n",
	    fd, VSL_tags[tag],
	    ((spec & VSL_S_CLIENT) ? 'c' : (spec & VSL_S_BACKEND) ? 'b' : ' '),
	    len, ptr);
	return (0);
}

/*--------------------------------------------------------------------*/

static int
vsl_r_arg(struct VSL_data *vd, const char *opt)
{

	CHECK_OBJ_NOTNULL(vd, VSL_MAGIC);
	if (!strcmp(opt, "-"))
		vd->fi = stdin;
	else
		vd->fi = fopen(opt, "r");
	if (vd->fi != NULL)
		return (1);
	perror(opt);
	return (-1);
}

/*--------------------------------------------------------------------*/

static int
vsl_IX_arg(struct VSL_data *vd, const char *opt, int arg)
{
	int i;
	regex_t **rp;
	char buf[BUFSIZ];

	CHECK_OBJ_NOTNULL(vd, VSL_MAGIC);
	if (arg == 'I')
		rp = &vd->regincl;
	else
		rp = &vd->regexcl;
	if (*rp != NULL) {
		fprintf(stderr, "Option %c can only be given once", arg);
		return (-1);
	}
	*rp = calloc(sizeof(regex_t), 1);
	if (*rp == NULL) {
		perror("malloc");
		return (-1);
	}
	i = regcomp(*rp, opt, vd->regflags);
	if (i) {
		regerror(i, *rp, buf, sizeof buf);
		fprintf(stderr, "%s", buf);
		return (-1);
	}
	return (1);
}

/*--------------------------------------------------------------------*/

static int
vsl_ix_arg(struct VSL_data *vd, const char *opt, int arg)
{
	int i, j, l;
	const char *b, *e, *p, *q;

	CHECK_OBJ_NOTNULL(vd, VSL_MAGIC);
	/* If first option is 'i', set all bits for supression */
	if (arg == 'i' && !(vd->flags & F_SEEN_IX))
		for (i = 0; i < 256; i++)
			vd->map[i] |= M_SUPPRESS;
	vd->flags |= F_SEEN_IX;

	for (b = opt; *b; b = e) {
		while (isspace(*b))
			b++;
		e = strchr(b, ',');
		if (e == NULL)
			e = strchr(b, '\0');
		l = e - b;
		if (*e == ',')
			e++;
		while (isspace(b[l - 1]))
			l--;
		for (i = 0; i < 256; i++) {
			if (VSL_tags[i] == NULL)
				continue;
			p = VSL_tags[i];
			q = b;
			for (j = 0; j < l; j++)
				if (tolower(*q++) != tolower(*p++))
					break;
			if (j != l || *p != '\0')
				continue;

			if (arg == 'x')
				vd->map[i] |= M_SUPPRESS;
			else
				vd->map[i] &= ~M_SUPPRESS;
			break;
		}
		if (i == 256) {
			fprintf(stderr,
			    "Could not match \"%*.*s\" to any tag\n", l, l, b);
			return (-1);
		}
	}
	return (1);
}

/*--------------------------------------------------------------------*/

int
VSL_Arg(struct VSL_data *vd, int arg, const char *opt)
{

	CHECK_OBJ_NOTNULL(vd, VSL_MAGIC);
	switch (arg) {
	case 'b': vd->b_opt = !vd->b_opt; return (1);
	case 'c': vd->c_opt = !vd->c_opt; return (1);
	case 'd': vd->d_opt = !vd->d_opt; return (1);
	case 'i': case 'x': return (vsl_ix_arg(vd, opt, arg));
	case 'r': return (vsl_r_arg(vd, opt));
	case 'I': case 'X': return (vsl_IX_arg(vd, opt, arg));
	case 'C': vd->regflags = REG_ICASE; return (1);
	default:
		return (0);
	}
}

struct varnish_stats *
VSL_OpenStats(char *varnish_name)
{

	if (vsl_shmem_map(varnish_name))
		return (NULL);
	return (&vsl_lh->stats);
}

