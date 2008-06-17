/*
 * Copyright (c) 2006-2008 Linpro AS
 * All rights reserved.
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


#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <ctype.h>

#include "libvarnish.h"
#include "vct.h"
#include "miniobj.h"
#include "vsb.h"

#include "vtc.h"

#define MAX_HDR		50

struct http {
	unsigned		magic;
#define HTTP_MAGIC		0x2f02169c
	int			fd;
	int			client;
	int			timeout;
	const char		*ident;

	int			nrxbuf;
	char			*rxbuf;

	char			*req[MAX_HDR];
	char			*resp[MAX_HDR];
};

/**********************************************************************
 * Expect
 */

static char *
cmd_var_resolve(struct http *hp, char *spec)
{
	char **hh, *hdr;
	int n, l;

	if (!strcmp(spec, "req.request"))
		return(hp->req[0]);
	if (!strcmp(spec, "req.url"))
		return(hp->req[1]);
	if (!strcmp(spec, "req.proto"))
		return(hp->req[2]);
	if (!strcmp(spec, "resp.proto"))
		return(hp->resp[0]);
	if (!strcmp(spec, "resp.status"))
		return(hp->resp[1]);
	if (!strcmp(spec, "resp.msg"))
		return(hp->resp[2]);
	if (!memcmp(spec, "req.http.", 9)) {
		hh = hp->req;
		hdr = spec + 9;
	} else if (!memcmp(spec, "resp.http.", 10)) {
		hh = hp->resp;
		hdr = spec + 10;
	} else
		return (spec);
	l = strlen(hdr);
	for (n = 3; hh[n] != NULL; n++) {
		if (strncasecmp(hdr, hh[n], l) || hh[n][l] != ':')
			continue;
		hdr = hh[n] + l + 1;
		while (vct_issp(*hdr))
			hdr++;
		return (hdr);
	}
	return (spec);
}

static void
cmd_http_expect(char **av, void *priv)
{
	struct http *hp;
	char *lhs;
	char *cmp;
	char *rhs;

	CAST_OBJ_NOTNULL(hp, priv, HTTP_MAGIC);
	assert(!strcmp(av[0], "expect"));
	av++;

	AN(av[0]);
	AN(av[1]);
	AN(av[2]);
	AZ(av[3]);
	lhs = cmd_var_resolve(hp, av[0]);
	cmp = av[1];
	rhs = cmd_var_resolve(hp, av[2]);
	if (!strcmp(cmp, "==")) {
		if (strcmp(lhs, rhs)) {
			fprintf(stderr, 
			    "---- %-4s EXPECT %s (%s) %s %s (%s) failed\n",
			    hp->ident, av[0], lhs, av[1], av[2], rhs);
			exit (1);
		} else {
			printf(
			    "#### %-4s EXPECT %s (%s) %s %s (%s) match\n",
			    hp->ident, av[0], lhs, av[1], av[2], rhs);
		}
	} else {
		fprintf(stderr, 
		    "---- %-4s EXPECT %s (%s) %s %s (%s) not implemented\n",
		    hp->ident, av[0], lhs, av[1], av[2], rhs);
		exit (1);
	}
}

/**********************************************************************
 * Split a HTTP protocol header
 */

static void
http_splitheader(struct http *hp, int req)
{
	char *p, *q, **hh;
	int n;
	char buf[20];

	CHECK_OBJ_NOTNULL(hp, HTTP_MAGIC);
	if (req) {
		memset(hp->req, 0, sizeof hp->req);
		hh = hp->req;
	} else {
		memset(hp->resp, 0, sizeof hp->resp);
		hh = hp->resp;
	}

	n = 0;
	p = hp->rxbuf;

	/* REQ/PROTO */
	while (vct_islws(*p))
		p++;
	hh[n++] = p;
	while (!vct_islws(*p))
		p++;
	assert(!vct_iscrlf(*p));
	*p++ = '\0';

	/* URL/STATUS */
	while (vct_issp(*p))		/* XXX: H space only */
		p++;
	assert(!vct_iscrlf(*p));
	hh[n++] = p;
	while (!vct_islws(*p))
		p++;
	if (vct_iscrlf(*p)) {
		hh[n++] = NULL;
		q = p;
		p += vct_skipcrlf(p);
		*q = '\0';
	} else {
		*p++ = '\0';
		/* PROTO/MSG */
		while (vct_issp(*p))		/* XXX: H space only */
			p++;
		hh[n++] = p;
		while (!vct_iscrlf(*p))
			p++;
		q = p;
		p += vct_skipcrlf(p);
		*q = '\0';
	}
	assert(n == 3);

	while (*p != '\0') {
		assert(n < MAX_HDR);
		if (vct_iscrlf(*p))
			break;
		hh[n++] = p++;
		while (*p != '\0' && !vct_iscrlf(*p))
			p++;
		q = p;
		p += vct_skipcrlf(p);
		*q = '\0';
	}
	p += vct_skipcrlf(p);
	assert(*p == '\0');

	for (n = 0; n < 3 || hh[n] != NULL; n++) {
		sprintf(buf, "http[%2d] ", n);
		vct_dump(hp->ident, buf, hh[n]);
	}
}


/**********************************************************************
 * Receive a HTTP protocol header
 */

static void
http_rxhdr(struct http *hp)
{
	int l, n, i;
	struct pollfd pfd[1];
	char *p;

	CHECK_OBJ_NOTNULL(hp, HTTP_MAGIC);
	hp->rxbuf = malloc(hp->nrxbuf);		/* XXX */
	AN(hp->rxbuf);
	l = 0;
	while (1) {
		pfd[0].fd = hp->fd;
		pfd[0].events = POLLIN;
		pfd[0].revents = 0;
		i = poll(pfd, 1, hp->timeout);
		assert(i > 0);
		assert(l < hp->nrxbuf);
		n = read(hp->fd, hp->rxbuf + l, 1);
		assert(n == 1);
		l += n;
		hp->rxbuf[l] = '\0';
		assert(n > 0);
		p = hp->rxbuf + l - 1;
		i = 0;
		for (i = 0; p > hp->rxbuf; p--) {
			if (*p != '\n') 
				break;
			if (p - 1 > hp->rxbuf && p[-1] == '\r')
				p--;
			if (++i == 2)
				break;
		}
		if (i == 2)
			break;
	}
	vct_dump(hp->ident, NULL, hp->rxbuf);
}


/**********************************************************************
 * Receive a response
 */

static void
cmd_http_rxresp(char **av, void *priv)
{
	struct http *hp;

	CAST_OBJ_NOTNULL(hp, priv, HTTP_MAGIC);
	AN(hp->client);
	assert(!strcmp(av[0], "rxresp"));
	av++;

	for(; *av != NULL; av++) {
		fprintf(stderr, "Unknown http rxresp spec: %s\n", *av);
		exit (1);
	}
	printf("###  %-4s rxresp\n", hp->ident);
	http_rxhdr(hp);
	http_splitheader(hp, 0);
}

/**********************************************************************
 * Transmit a response
 */

static void
cmd_http_txresp(char **av, void *priv)
{
	struct http *hp;
	struct vsb *vsb;
	const char *proto = "HTTP/1.1";
	const char *status = "200";
	const char *msg = "Ok";
	const char *body = NULL;
	int dohdr = 0;
	const char *nl = "\r\n";
	int l;

	CAST_OBJ_NOTNULL(hp, priv, HTTP_MAGIC);
	AZ(hp->client);
	assert(!strcmp(av[0], "txresp"));
	av++;

	vsb = vsb_newauto();

	for(; *av != NULL; av++) {
		if (!strcmp(*av, "-proto")) {
			AZ(dohdr);
			proto = av[1];
			av++;
			continue;
		}
		if (!strcmp(*av, "-status")) {
			AZ(dohdr);
			status = av[1];
			av++;
			continue;
		}
		if (!strcmp(*av, "-msg")) {
			AZ(dohdr);
			msg = av[1];
			av++;
			continue;
		}
		if (!strcmp(*av, "-body")) {
			body = av[1];
			av++;
			continue;
		}
		if (!strcmp(*av, "-hdr")) {
			if (dohdr == 0) {
				vsb_printf(vsb, "%s %s %s%s", 
				    proto, status, msg, nl);
				dohdr = 1;
			}
			vsb_printf(vsb, "%s%s", av[1], nl);
			av++;
			continue;
		}
		fprintf(stderr, "Unknown http txreq spec: %s\n", *av);
		exit (1);
	}
	if (dohdr == 0) {
		vsb_printf(vsb, "%s %s %s%s", 
		    proto, status, msg, nl);
		dohdr = 1;
	}
	vsb_cat(vsb, nl);
	if (body != NULL) {
		vsb_cat(vsb, body);
		vsb_cat(vsb, nl);
	}
	vsb_finish(vsb);
	AZ(vsb_overflowed(vsb));
	vct_dump(hp->ident, NULL, vsb_data(vsb));
	l = write(hp->fd, vsb_data(vsb), vsb_len(vsb));
	assert(l == vsb_len(vsb));
	vsb_delete(vsb);
}

/**********************************************************************
 * Receive a request
 */

static void
cmd_http_rxreq(char **av, void *priv)
{
	struct http *hp;

	CAST_OBJ_NOTNULL(hp, priv, HTTP_MAGIC);
	AZ(hp->client);
	assert(!strcmp(av[0], "rxreq"));
	av++;

	for(; *av != NULL; av++) {
		fprintf(stderr, "Unknown http rxreq spec: %s\n", *av);
		exit (1);
	}
	printf("###  %-4s rxreq\n", hp->ident);
	http_rxhdr(hp);
	http_splitheader(hp, 1);
}

/**********************************************************************
 * Transmit a request
 */

static void
cmd_http_txreq(char **av, void *priv)
{
	struct http *hp;
	struct vsb *vsb;
	const char *req = "GET";
	const char *url = "/";
	const char *proto = "HTTP/1.1";
	int dohdr = 0;
	const char *nl = "\r\n";
	int l;

	CAST_OBJ_NOTNULL(hp, priv, HTTP_MAGIC);
	AN(hp->client);
	assert(!strcmp(av[0], "txreq"));
	av++;

	vsb = vsb_newauto();

	for(; *av != NULL; av++) {
		if (!strcmp(*av, "-url")) {
			AZ(dohdr);
			url = av[1];
			av++;
			continue;
		}
		if (!strcmp(*av, "-proto")) {
			AZ(dohdr);
			proto = av[1];
			av++;
			continue;
		}
		if (!strcmp(*av, "-req")) {
			AZ(dohdr);
			req = av[1];
			av++;
			continue;
		}
		if (!strcmp(*av, "-hdr")) {
			if (dohdr == 0) {
				vsb_printf(vsb, "%s %s %s%s", 
				    req, url, proto, nl);
				dohdr = 1;
			}
			vsb_printf(vsb, "%s%s", av[1], nl);
			av++;
			continue;
		}
		fprintf(stderr, "Unknown http txreq spec: %s\n", *av);
		exit (1);
	}
	if (dohdr == 0) {
		vsb_printf(vsb, "%s %s %s%s", 
		    req, url, proto, nl);
		dohdr = 1;
	}
	vsb_cat(vsb, nl);
	vsb_finish(vsb);
	AZ(vsb_overflowed(vsb));
	vct_dump(hp->ident, NULL, vsb_data(vsb));
	l = write(hp->fd, vsb_data(vsb), vsb_len(vsb));
	assert(l == vsb_len(vsb));
	vsb_delete(vsb);
}

/**********************************************************************
 * Execute HTTP specifications
 */

static struct cmds http_cmds[] = {
	{ "txreq",	cmd_http_txreq },
	{ "rxreq",	cmd_http_rxreq },
	{ "txresp",	cmd_http_txresp },
	{ "rxresp",	cmd_http_rxresp },
	{ "expect",	cmd_http_expect },
	{ "delay",	cmd_delay },
	{ NULL,		NULL }
};

void
http_process(const char *ident, const char *spec, int sock, int client)
{
	struct http *hp;
	char *s, *q;

	ALLOC_OBJ(hp, HTTP_MAGIC);
	AN(hp);
	hp->fd = sock;
	hp->ident = ident;
	hp->client = client;
	hp->timeout = 1000;
	hp->nrxbuf = 8192;

	s = strdup(spec + 1);
	q = strchr(s, '\0');
	assert(q > s);
	q--;
	assert(*q == '}');
	*q = '\0';
	AN(s);
	parse_string(s, http_cmds, hp);
	free(hp);
}
