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
 * Manage backend connections and requests.
 *
 */

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <poll.h>

#include <sys/socket.h>
#include <netdb.h>

#include "heritage.h"
#include "shmlog.h"
#include "cache.h"

static VTAILQ_HEAD(,bereq) bereq_head = VTAILQ_HEAD_INITIALIZER(bereq_head);
static VTAILQ_HEAD(,vbe_conn) vbe_head = VTAILQ_HEAD_INITIALIZER(vbe_head);

static MTX VBE_mtx;

struct backendlist backendlist = VTAILQ_HEAD_INITIALIZER(backendlist);


/*--------------------------------------------------------------------
 * Attempt to connect to a given addrinfo entry.
 *
 * Must be called with locked backend, but will release the backend
 * lock during the slow/sleeping stuff, so that other worker threads
 * can have a go, while we ponder.
 *
 */

int
VBE_TryConnect(const struct sess *sp, const struct addrinfo *ai)
{
	struct sockaddr_storage ss;
	int fam, sockt, proto;
	socklen_t alen;
	int s;
	char abuf1[TCP_ADDRBUFSIZE], abuf2[TCP_ADDRBUFSIZE];
	char pbuf1[TCP_PORTBUFSIZE], pbuf2[TCP_PORTBUFSIZE];

	/*
	 * ai is only valid with the lock held, so copy out the bits
	 * we need to make the connection
	 */
	fam = ai->ai_family;
	sockt = ai->ai_socktype;
	proto = ai->ai_protocol;
	alen = ai->ai_addrlen;
	assert(alen <= sizeof ss);
	memcpy(&ss, ai->ai_addr, alen);

	/* release lock during stuff that can take a long time */
	UNLOCK(&sp->backend->mtx);

	s = socket(fam, sockt, proto);
	if (s < 0) {
		LOCK(&sp->backend->mtx);
		return (s);
	}

	if (connect(s, (void *)&ss, alen) != 0) {
		AZ(close(s));
		LOCK(&sp->backend->mtx);
		return (-1);
	}

	TCP_myname(s, abuf1, sizeof abuf1, pbuf1, sizeof pbuf1);
	TCP_name((void*)&ss, alen,
	    abuf2, sizeof abuf2, pbuf2, sizeof pbuf2);
	WSL(sp->wrk, SLT_BackendOpen, s, "%s %s %s %s %s",
	    sp->backend->vcl_name, abuf1, pbuf1, abuf2, pbuf2);

	LOCK(&sp->backend->mtx);
	return (s);
}

/*--------------------------------------------------------------------
 * Check that there is still something at the far end of a given fd.
 * We poll the fd with instant timeout, if there are any events we can't
 * use it (backends are not allowed to pipeline).
 */

int
VBE_CheckFd(int fd)
{
	struct pollfd pfd;

	pfd.fd = fd;
	pfd.events = POLLIN;
	pfd.revents = 0;
	return(poll(&pfd, 1, 0) == 0);
}

/*--------------------------------------------------------------------
 * Get a http structure for talking to the backend.
 */

struct bereq *
VBE_new_bereq(void)
{
	struct bereq *bereq;
	volatile unsigned len;

	LOCK(&VBE_mtx);
	bereq = VTAILQ_FIRST(&bereq_head);
	if (bereq != NULL)
		VTAILQ_REMOVE(&bereq_head, bereq, list);
	UNLOCK(&VBE_mtx);
	if (bereq != NULL) {
		CHECK_OBJ(bereq, BEREQ_MAGIC);
	} else {
		len =  params->mem_workspace;
		bereq = calloc(sizeof *bereq + len, 1);
		if (bereq == NULL)
			return (NULL);
		bereq->magic = BEREQ_MAGIC;
		bereq->space = bereq + 1;
		bereq->len = len;
	}
	http_Setup(bereq->http, bereq->space, bereq->len);
	return (bereq);
}

/*--------------------------------------------------------------------*/
/* XXX: no backpressure on pool size */

void
VBE_free_bereq(struct bereq *bereq)
{

	CHECK_OBJ_NOTNULL(bereq, BEREQ_MAGIC);
	LOCK(&VBE_mtx);
	VTAILQ_INSERT_HEAD(&bereq_head, bereq, list);
	UNLOCK(&VBE_mtx);
}

/*--------------------------------------------------------------------*/

struct vbe_conn *
VBE_NewConn(void)
{
	struct vbe_conn *vc;

	vc = VTAILQ_FIRST(&vbe_head);
	if (vc != NULL) {
		LOCK(&VBE_mtx);
		vc = VTAILQ_FIRST(&vbe_head);
		if (vc != NULL) {
			VSL_stats->backend_unused--;
			VTAILQ_REMOVE(&vbe_head, vc, list);
		} else {
			VSL_stats->n_vbe_conn++;
		}
		UNLOCK(&VBE_mtx);
	}
	if (vc != NULL)
		return (vc);

	vc = calloc(sizeof *vc, 1);
	XXXAN(vc);
	vc->magic = VBE_CONN_MAGIC;
	vc->fd = -1;
	return (vc);
}

/*--------------------------------------------------------------------*/

void
VBE_ReleaseConn(struct vbe_conn *vc)
{

	CHECK_OBJ_NOTNULL(vc, VBE_CONN_MAGIC);
	assert(vc->backend == NULL);
	assert(vc->fd < 0);
	LOCK(&VBE_mtx);
	VTAILQ_INSERT_HEAD(&vbe_head, vc, list);
	VSL_stats->backend_unused++;
	UNLOCK(&VBE_mtx);
}

/*--------------------------------------------------------------------*/

struct backend *
VBE_NewBackend(struct backend_method *method)
{
	struct backend *b;

	b = calloc(sizeof *b, 1);
	XXXAN(b);
	b->magic = BACKEND_MAGIC;
	b->method = method;

	MTX_INIT(&b->mtx);
	b->refcount = 1;

	b->last_check = TIM_mono();
	b->minute_limit = 1;

	VTAILQ_INSERT_TAIL(&backendlist, b, list);
	return (b);
}

/*--------------------------------------------------------------------*/

void
VBE_DropRefLocked(struct backend *b)
{
	int i;

	CHECK_OBJ_NOTNULL(b, BACKEND_MAGIC);

	i = --b->refcount;
	if (i == 0)
		VTAILQ_REMOVE(&backendlist, b, list);
	UNLOCK(&b->mtx);
	if (i)
		return;
	b->magic = 0;
	b->method->cleanup(b);
	free(b->vcl_name);
	free(b);
}

void
VBE_DropRef(struct backend *b)
{

	CHECK_OBJ_NOTNULL(b, BACKEND_MAGIC);

	LOCK(&b->mtx);
	VBE_DropRefLocked(b);
}

/*--------------------------------------------------------------------*/

struct vbe_conn *
VBE_GetFd(const struct sess *sp)
{

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	CHECK_OBJ_NOTNULL(sp->backend, BACKEND_MAGIC);
	AN(sp->backend->method);
	AN(sp->backend->method->getfd);
	return(sp->backend->method->getfd(sp));
}

/* Close a connection ------------------------------------------------*/

void
VBE_ClosedFd(struct worker *w, struct vbe_conn *vc)
{
	struct backend *b;

	CHECK_OBJ_NOTNULL(vc, VBE_CONN_MAGIC);
	CHECK_OBJ_NOTNULL(vc->backend, BACKEND_MAGIC);
	b = vc->backend;
	AN(b->method);
	AN(b->method->close);
	b->method->close(w, vc);
	CHECK_OBJ_NOTNULL(b, BACKEND_MAGIC);
}

/* Recycle a connection ----------------------------------------------*/

void
VBE_RecycleFd(struct worker *w, struct vbe_conn *vc)
{
	struct backend *b;

	CHECK_OBJ_NOTNULL(vc, VBE_CONN_MAGIC);
	CHECK_OBJ_NOTNULL(vc->backend, BACKEND_MAGIC);
	b = vc->backend;
	AN(b->method);
	AN(b->method->recycle);
	b->method->recycle(w, vc);
	CHECK_OBJ_NOTNULL(b, BACKEND_MAGIC);
}

/* Update health ----------------------------------------------------*/
/* See cache_backend_random.c and/or cache_backend_round_robin.c for
 * details and comments about this function. 
 */
void
VBE_UpdateHealth(const struct sess *sp, const struct vbe_conn *vc, int a)
{
	struct backend *b;

	if (vc != NULL) {
		CHECK_OBJ_NOTNULL(vc, VBE_CONN_MAGIC);
		CHECK_OBJ_NOTNULL(vc->backend, BACKEND_MAGIC);
		b = vc->backend;
	}
	else {
		CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
		CHECK_OBJ_NOTNULL(sp->backend, BACKEND_MAGIC);
		b = sp->backend;
	}
	AN(b->method);
	if(b->method->updatehealth != NULL)
		b->method->updatehealth(sp, vc, a);
	CHECK_OBJ_NOTNULL(b, BACKEND_MAGIC);
}

/*--------------------------------------------------------------------*/

static void
VBE_AddBackendMethod(const struct backend_method *bem)
{

	if (bem->init != NULL)
		bem->init();
}

/*--------------------------------------------------------------------*/

void
VBE_Init(void)
{

	MTX_INIT(&VBE_mtx);
	VBE_AddBackendMethod(&backend_method_simple);
	VBE_AddBackendMethod(&backend_method_random);
	VBE_AddBackendMethod(&backend_method_round_robin);
}
