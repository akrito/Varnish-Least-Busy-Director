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
 *
 * Runtime support for compiled VCL programs
 */

#include <sys/types.h>
#include <sys/socket.h>

#include <netinet/in.h>

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>

#include "shmlog.h"
#include "heritage.h"
#include "vrt.h"
#include "vrt_obj.h"
#include "vcl.h"
#include "cache.h"

/*--------------------------------------------------------------------*/

void
VRT_error(struct sess *sp, unsigned code, const char *reason)
{

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	WSL(sp->wrk, SLT_Debug, 0, "VCL_error(%u, %s)", code, reason);
	sp->err_code = code ? code : 503;
	sp->err_reason = reason ? reason : http_StatusMessage(sp->err_code);
}

/*--------------------------------------------------------------------*/

void
VRT_count(const struct sess *sp, unsigned u)
{

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	if (params->vcl_trace)
		WSP(sp, SLT_VCL_trace, "%u %d.%d", u,
		    sp->vcl->ref[u].line, sp->vcl->ref[u].pos);
}

/*--------------------------------------------------------------------*/

static struct http *
vrt_selecthttp(const struct sess *sp, enum gethdr_e where)
{
	struct http *hp;

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	switch (where) {
	case HDR_REQ:
		hp = sp->http;
		break;
	case HDR_BEREQ:
		hp = sp->bereq->http;
		break;
	case HDR_RESP:
		hp = sp->http;
		break;
	case HDR_OBJ:
		hp = sp->obj->http;
		break;
	default:
		INCOMPL();
	}
	CHECK_OBJ_NOTNULL(hp, HTTP_MAGIC);
	return (hp);
}

char *
VRT_GetHdr(const struct sess *sp, enum gethdr_e where, const char *n)
{
	char *p;
	struct http *hp;

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	hp = vrt_selecthttp(sp, where);
	if (!http_GetHdr(hp, n, &p))
		return (NULL);
	return (p);
}

/*--------------------------------------------------------------------*/

static char *
vrt_assemble_string(struct http *hp, const char *h, const char *p, va_list ap)
{
	char *b, *e;
	unsigned u, x;

	u = WS_Reserve(hp->ws, 0);
	e = b = hp->ws->f;
	e += u;
	if (h != NULL) {
		x = strlen(h);
		if (b + x < e)
			memcpy(b, h, x);
		b += x;
		if (b + 1 < e) 
			*b++ = ' ';
	}
	while (p != NULL) {
		x = strlen(p);
		if (b + x < e)
			memcpy(b, p, x);
		b += x;
		p = va_arg(ap, const char *);
	}
	if (b + 1 < e) 
		*b++ = '\0';
	if (b > e) {
		WS_Release(hp->ws, 0);
		return (NULL);
	} else {
		e = b;
		b = hp->ws->f;
		WS_Release(hp->ws, 1 + e - b);
		return (b);
	}
}

/*--------------------------------------------------------------------*/

void
VRT_SetHdr(const struct sess *sp , enum gethdr_e where, const char *hdr, const char *p, ...)
{
	struct http *hp;
	va_list ap;
	char *b;

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	hp = vrt_selecthttp(sp, where);
	va_start(ap, p);
	if (p == NULL) {
		http_Unset(hp, hdr);
	} else {
		b = vrt_assemble_string(hp, hdr + 1, p, ap);
		if (b == NULL) {
			WSP(sp, SLT_LostHeader, "%s", hdr + 1);
		} else {
			http_Unset(hp, hdr);
			http_SetHeader(sp->wrk, sp->fd, hp, b);
		}
	}
	va_end(ap);
}

/*--------------------------------------------------------------------*/

static void
vrt_do_string(struct worker *w, int fd, struct http *hp, int fld, const char *err, const char *p, va_list ap)
{
	char *b;

	AN(p);
	AN(hp);
	b = vrt_assemble_string(hp, NULL, p, ap);
	if (b == NULL) {
		WSL(w, SLT_LostHeader, fd, err);
	} else {
		http_SetH(hp, fld, b);
	}
	va_end(ap);
}

#define VRT_DO_HDR(obj, hdr, http, fld)				\
void								\
VRT_l_##obj##_##hdr(const struct sess *sp, const char *p, ...)	\
{								\
	va_list ap;						\
								\
	AN(p);							\
	va_start(ap, p);					\
	vrt_do_string(sp->wrk, sp->fd,				\
	    http, fld, #obj "." #hdr, p, ap);			\
	va_end(ap);						\
}

VRT_DO_HDR(req,   request,	sp->http,		HTTP_HDR_REQ)
VRT_DO_HDR(req,   url,		sp->http,		HTTP_HDR_URL)
VRT_DO_HDR(req,   proto,	sp->http,		HTTP_HDR_PROTO)
VRT_DO_HDR(bereq, request,	sp->bereq->http,	HTTP_HDR_REQ)
VRT_DO_HDR(bereq, url,		sp->bereq->http,	HTTP_HDR_URL)
VRT_DO_HDR(bereq, proto,	sp->bereq->http,	HTTP_HDR_PROTO)
VRT_DO_HDR(obj,   proto,	sp->obj->http,		HTTP_HDR_PROTO)
VRT_DO_HDR(obj,   response,	sp->obj->http,		HTTP_HDR_RESPONSE)
VRT_DO_HDR(resp,  proto,	sp->http,		HTTP_HDR_PROTO)
VRT_DO_HDR(resp,  response,	sp->http,		HTTP_HDR_RESPONSE)

void
VRT_l_obj_status(const struct sess *sp, int num)
{
	char *p;

	assert(num >= 100 && num <= 999);
	p = WS_Alloc(sp->obj->http->ws, 4);
	if (p == NULL)
		WSP(sp, SLT_LostHeader, "%s", "obj.status");
	else
		sprintf(p, "%d", num);
	http_SetH(sp->obj->http, HTTP_HDR_STATUS, p);
}

int
VRT_r_obj_status(const struct sess *sp)
{
	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	CHECK_OBJ_NOTNULL(sp->obj, OBJECT_MAGIC);
	/* XXX: use http_GetStatus() */
	if (sp->obj->http->status)
		return (sp->obj->http->status);
	return (atoi(sp->obj->http->hd[HTTP_HDR_STATUS].b));
}

void
VRT_l_resp_status(const struct sess *sp, int num)
{
	char *p;

	assert(num >= 100 && num <= 999);
	p = WS_Alloc(sp->http->ws, 4);
	if (p == NULL)
		WSP(sp, SLT_LostHeader, "%s", "resp.status");
	else
		sprintf(p, "%d", num);
	http_SetH(sp->http, HTTP_HDR_STATUS, p);
}

/*--------------------------------------------------------------------*/

void
VRT_handling(struct sess *sp, unsigned hand)
{

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	assert(!(hand & (hand -1)));	/* must be power of two */
	sp->handling = hand;
}

/*--------------------------------------------------------------------
 * XXX: Working relative to t_req is maybe not the right thing, we could
 * XXX: have spent a long time talking to the backend since then.
 * XXX: It might make sense to cache a timestamp as "current time"
 * XXX: before vcl_recv (== t_req) and vcl_fetch.
 * XXX: On the other hand, that might lead to inconsistent behaviour
 * XXX: where an object expires while we are running VCL code, and
 * XXX: and that may not be a good idea either.
 * XXX: See also related t_req use in cache_hash.c
 */

void
VRT_l_obj_ttl(const struct sess *sp, double a)
{

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	CHECK_OBJ_NOTNULL(sp->obj, OBJECT_MAGIC);	/* XXX */
	WSP(sp, SLT_TTL, "%u VCL %.0f %.0f",
	    sp->obj->xid, a, sp->t_req);
	if (a < 0)
		a = 0;
	sp->obj->ttl = sp->t_req + a;
	if (sp->obj->timer_idx != 0)
		EXP_TTLchange(sp->obj);
}

double
VRT_r_obj_ttl(const struct sess *sp)
{
	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	CHECK_OBJ_NOTNULL(sp->obj, OBJECT_MAGIC);	/* XXX */
	return (sp->obj->ttl - sp->t_req);
}

/*--------------------------------------------------------------------*/

/* XXX: the VCL_info messages has unexpected fractions on the ttl */

void
VRT_l_obj_prefetch(const struct sess *sp, double a)
{

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	CHECK_OBJ_NOTNULL(sp->obj, OBJECT_MAGIC);	/* XXX */
	sp->obj->prefetch = 0.0;
	if (a == 0.0)
		sp->obj->prefetch = a;
	else if (a > 0.0 && a + sp->t_req <= sp->obj->ttl)
		sp->obj->prefetch = a + sp->t_req;
	else if (a < 0.0 && a + sp->obj->ttl > sp->t_req)
		sp->obj->prefetch = a;
	else if (a > 0.0)
		WSL(sp->wrk, SLT_VCL_info, sp->id,
		    "XID %u: obj.prefetch (%g) after TTL (%g), ignored.",
		    sp->obj->xid, a, sp->obj->ttl - sp->t_req);
	else /* if (a < 0.0) */
		WSL(sp->wrk, SLT_VCL_info, sp->id,
		    "XID %u: obj.prefetch (%g) less than ttl (%g), ignored.",
		    sp->obj->xid, a, sp->obj->ttl - sp->t_req);
	if (sp->obj->timer_idx != 0)
		EXP_TTLchange(sp->obj);
}

double
VRT_r_obj_prefetch(const struct sess *sp)
{
	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	CHECK_OBJ_NOTNULL(sp->obj, OBJECT_MAGIC);	/* XXX */
	return (sp->obj->prefetch - sp->t_req);
}

/*--------------------------------------------------------------------*/

#define VOBJ(type,onm,field)						\
void									\
VRT_l_obj_##onm(const struct sess *sp, type a)				\
{									\
	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);				\
	CHECK_OBJ_NOTNULL(sp->obj, OBJECT_MAGIC);	/* XXX */	\
	sp->obj->field = a;						\
}									\
									\
type									\
VRT_r_obj_##onm(const struct sess *sp)					\
{									\
	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);				\
	CHECK_OBJ_NOTNULL(sp->obj, OBJECT_MAGIC);	/* XXX */	\
	return (sp->obj->field);					\
}

VOBJ(unsigned, valid, valid)
VOBJ(unsigned, cacheable, cacheable)

/*--------------------------------------------------------------------*/

void
VRT_l_req_backend(struct sess *sp, struct backend *be)
{
	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	sp->backend = be;
}

struct backend *
VRT_r_req_backend(struct sess *sp)
{
	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	return (sp->backend);
}

/*--------------------------------------------------------------------*/

#define  VREQ(n1, n2)					\
const char *						\
VRT_r_req_##n1(const struct sess *sp)				\
{							\
	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);		\
	CHECK_OBJ_NOTNULL(sp->http, HTTP_MAGIC);	\
	return (sp->http->hd[n2].b);			\
}

VREQ(request, HTTP_HDR_REQ)
VREQ(url, HTTP_HDR_URL)
VREQ(proto, HTTP_HDR_PROTO)

/*--------------------------------------------------------------------*/

int
VRT_r_req_restarts(const struct sess *sp)
{

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	return (sp->restarts);
}

/*--------------------------------------------------------------------*/

const char *
VRT_r_resp_proto(const struct sess *sp)
{
	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	CHECK_OBJ_NOTNULL(sp->obj, OBJECT_MAGIC);
	return (sp->obj->http->hd[HTTP_HDR_PROTO].b);
}

const char *
VRT_r_resp_response(const struct sess *sp)
{
	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	CHECK_OBJ_NOTNULL(sp->obj, OBJECT_MAGIC);
	return (sp->obj->http->hd[HTTP_HDR_RESPONSE].b);
}

int
VRT_r_resp_status(const struct sess *sp)
{
	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	CHECK_OBJ_NOTNULL(sp->obj, OBJECT_MAGIC);
	return (atoi(sp->obj->http->hd[HTTP_HDR_STATUS].b));
}

/*--------------------------------------------------------------------*/

struct sockaddr *
VRT_r_client_ip(const struct sess *sp)
{

	return (sp->sockaddr);
}

struct sockaddr *
VRT_r_server_ip(struct sess *sp)
{

	if (sp->mysockaddr->sa_family == AF_UNSPEC)
		AZ(getsockname(sp->fd, sp->mysockaddr, &sp->mysockaddrlen));

	return (sp->mysockaddr);
}

/*--------------------------------------------------------------------
 * Add an element to the array/list of hash bits.
 */

void
VRT_l_req_hash(struct sess *sp, const char *str)
{
	int l;

	if (str == NULL)
		str = "";
	l = strlen(str);

	/*
	 * XXX: handle this by bouncing sp->vcl->nhashcount when it fails
	 * XXX: and dispose of this request either by reallocating the
	 * XXX: hashptr (if possible) or restarting/error the request
	 */
	xxxassert(sp->ihashptr < sp->nhashptr);

	sp->hashptr[sp->ihashptr] = str;
	sp->hashptr[sp->ihashptr + 1] = str + l;
	sp->ihashptr += 2;
	sp->lhashptr += l + 1;
}

/*--------------------------------------------------------------------*/

double
VRT_r_now(const struct sess *sp)
{

	(void)sp;
	return (TIM_mono());
}

double
VRT_r_obj_lastuse(const struct sess *sp)
{

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	CHECK_OBJ_NOTNULL(sp->obj, OBJECT_MAGIC);	/* XXX */
	return (TIM_mono() - sp->obj->lru_stamp);
}

int
VRT_r_backend_health(const struct sess *sp)
{
	
	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	CHECK_OBJ_NOTNULL(sp->backend, BACKEND_MAGIC);
	return (sp->backend->health);
}

/*--------------------------------------------------------------------*/

char *
VRT_IP_string(const struct sess *sp, const struct sockaddr *sa)
{
	char h[64], p[8], *q;
	socklen_t len = 0;

	/* XXX can't rely on sockaddr.sa_len */
	switch (sa->sa_family) {
	case AF_INET:
		len = sizeof(struct sockaddr_in);
		break;
	case AF_INET6:
		len = sizeof(struct sockaddr_in6);
		break;
	default:
		INCOMPL();
	}
	XXXAN(len);
	TCP_name(sa, len, h, sizeof h, p, sizeof p);
	q = WS_Alloc(sp->http->ws, strlen(h) + strlen(p) + 2);
	AN(q);
	strcpy(q, h);
	strcat(q, ":");
	strcat(q, p);
	return (q);
}

char *
VRT_int_string(const struct sess *sp, int num)
{
	char *p;
	int size = 12;
	
	p = WS_Alloc(sp->http->ws, size);
	AN(p);
	assert(snprintf(p, size, "%d", num) < size);
	return (p);
}

/*--------------------------------------------------------------------*/

void
VRT_Rollback(struct sess *sp)
{

	*sp->http = *sp->http0;
	WS_Reset(sp->ws, sp->ws_req);
}
	
/*--------------------------------------------------------------------*/

void
VRT_purge(const char *regexp, int hash)
{
	
	AddBan(regexp, hash);
}

/*--------------------------------------------------------------------
 * Simple stuff
 */

int
VRT_strcmp(const char *s1, const char *s2)
{
	if (s1 == NULL || s2 == NULL)
		return(1);
	return (strcmp(s1, s2));
}


/*--------------------------------------------------------------------
 * Backend stuff
 */

void
VRT_fini_backend(struct backend *b)
{

	VBE_DropRef(b);	
}
