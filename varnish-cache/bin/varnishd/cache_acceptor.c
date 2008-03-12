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
 *
 * XXX: We need to pass sessions back into the event engine when they are
 * reused.  Not sure what the most efficient way is for that.  For now
 * write the session pointer to a pipe which the event engine monitors.
 */

#include "config.h"

#include <stdio.h>
#include <errno.h>
#include <poll.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

#include <sys/uio.h>
#include <sys/types.h>
#include <sys/socket.h>

#ifndef HAVE_SRANDOMDEV
#include "compat/srandomdev.h"
#endif

#include "cli.h"
#include "cli_priv.h"
#include "shmlog.h"
#include "cache.h"
#include "cache_acceptor.h"

static struct acceptor *vca_acceptors[] = {
#if defined(HAVE_KQUEUE)
	&acceptor_kqueue,
#endif
#if defined(HAVE_EPOLL_CTL)
	&acceptor_epoll,
#endif
#if defined(HAVE_POLL)
	&acceptor_poll,
#endif
	NULL,
};

static struct acceptor *vca_act;

static pthread_t 	vca_thread_acct;
static struct timeval	tv_sndtimeo;
static struct timeval	tv_rcvtimeo;
static struct linger	linger;

static unsigned char	need_sndtimeo, need_rcvtimeo, need_linger, need_test;

int vca_pipes[2];

static void
sock_test(int fd)
{
	struct linger lin;
	struct timeval tv;
	socklen_t l;

	l = sizeof lin;
	AZ(getsockopt(fd, SOL_SOCKET, SO_LINGER, &lin, &l));
	assert(l == sizeof lin);
	if (memcmp(&lin, &linger, l))
		need_linger = 1;

#ifdef SO_SNDTIMEO_WORKS
	l = sizeof tv;
	AZ(getsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, &l));
	assert(l == sizeof tv);
	if (memcmp(&tv, &tv_sndtimeo, l))
		need_sndtimeo = 1;
#endif

#ifdef SO_RCVTIMEO_WORKS
	l = sizeof tv;
	AZ(getsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, &l));
	assert(l == sizeof tv);
	if (memcmp(&tv, &tv_rcvtimeo, l))
		need_rcvtimeo = 1;
#endif

	need_test = 0;
}

void
VCA_Prep(struct sess *sp)
{
	char addr[TCP_ADDRBUFSIZE];
	char port[TCP_PORTBUFSIZE];


	TCP_name(sp->sockaddr, sp->sockaddrlen,
	    addr, sizeof addr, port, sizeof port);
	sp->addr = WS_Dup(sp->ws, addr);
	sp->port = WS_Dup(sp->ws, port);
	VSL(SLT_SessionOpen, sp->fd, "%s %s", sp->addr, sp->port);
	sp->acct.first = sp->t_open;
	if (need_test)
		sock_test(sp->fd);
	if (need_linger)
		AZ(setsockopt(sp->fd, SOL_SOCKET, SO_LINGER,
		    &linger, sizeof linger));
#ifdef SO_SNDTIMEO_WORKS
	if (need_sndtimeo)
		AZ(setsockopt(sp->fd, SOL_SOCKET, SO_SNDTIMEO,
		    &tv_sndtimeo, sizeof tv_sndtimeo));
#endif
#ifdef SO_RCVTIMEO_WORKS
	if (need_rcvtimeo)
		AZ(setsockopt(sp->fd, SOL_SOCKET, SO_RCVTIMEO,
		    &tv_rcvtimeo, sizeof tv_rcvtimeo));
#endif
}

/*--------------------------------------------------------------------*/

static void *
vca_acct(void *arg)
{
	struct sess *sp;
	socklen_t l;
	struct sockaddr_storage addr_s;
	struct sockaddr *addr;
	int i;
	struct pollfd *pfd;
	struct listen_sock *ls;
	unsigned u;
	double now;

	THR_Name("cache-acceptor");
	(void)arg;

	/* Set up the poll argument */
	pfd = calloc(sizeof *pfd, heritage.nsocks);
	AN(pfd);
	i = 0;
	VTAILQ_FOREACH(ls, &heritage.socks, list) {
		AZ(setsockopt(ls->sock, SOL_SOCKET, SO_LINGER,
		    &linger, sizeof linger));
		pfd[i].events = POLLIN;
		pfd[i++].fd = ls->sock;
	}

	need_test = 1;
	while (1) {
#ifdef SO_SNDTIMEO_WORKS
		if (params->send_timeout != tv_sndtimeo.tv_sec) {
			need_test = 1;
			tv_sndtimeo.tv_sec = params->send_timeout;
			VTAILQ_FOREACH(ls, &heritage.socks, list) 
				AZ(setsockopt(ls->sock, SOL_SOCKET,
				    SO_SNDTIMEO,
				    &tv_sndtimeo, sizeof tv_sndtimeo));
		}
#endif
#ifdef SO_RCVTIMEO_WORKS
		if (params->sess_timeout != tv_rcvtimeo.tv_sec) {
			need_test = 1;
			tv_rcvtimeo.tv_sec = params->sess_timeout;
			VTAILQ_FOREACH(ls, &heritage.socks, list) 
				AZ(setsockopt(ls->sock, SOL_SOCKET,
				    SO_RCVTIMEO,
				    &tv_rcvtimeo, sizeof tv_rcvtimeo));
		}
#endif
		i = poll(pfd, heritage.nsocks, 1000);
		now = TIM_real();
		for (u = 0; u < heritage.nsocks; u++) {
			if (pfd[u].revents == 0)
				continue;
			VSL_stats->client_conn++;
			l = sizeof addr_s;
			addr = (void*)&addr_s;
			i = accept(pfd[u].fd, addr, &l);
			if (i < 0) {
				if (errno != EAGAIN) {
					VSL(SLT_Debug, pfd[u].fd,
					    "Accept failed errno=%d", errno);
					/* XXX: stats ? */
				}
				continue;
			}
			sp = SES_New(addr, l);
			XXXAN(sp);

			sp->fd = i;
			sp->id = i;
			sp->t_open = now;

			sp->step = STP_FIRST;
			WRK_QueueSession(sp);
		}
	}
}

/*--------------------------------------------------------------------*/

void
vca_handover(struct sess *sp, int status)
{

	switch (status) {
	case -2:
		vca_close_session(sp, "blast");
		SES_Delete(sp);
		break;
	case -1:
		vca_close_session(sp, "no request");
		SES_Delete(sp);
		break;
	case 1:
		sp->step = STP_START;
		WRK_QueueSession(sp);
		break;
	default:
		INCOMPL();
	}
}

/*--------------------------------------------------------------------*/

void
vca_close_session(struct sess *sp, const char *why)
{
	int i;

	VSL(SLT_SessionClose, sp->id, "%s", why);
	if (sp->fd >= 0) {
		i = close(sp->fd);
		assert(i == 0 || errno != EBADF);	/* XXX EINVAL seen */
	}
	sp->fd = -1;
}

void
vca_return_session(struct sess *sp)
{

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	AZ(sp->obj);
	AZ(sp->vcl);
	assert(sp->fd >= 0);
	assert(sizeof sp == write(vca_pipes[1], &sp, sizeof sp));
}


/*--------------------------------------------------------------------*/

static void
ccf_start(struct cli *cli, const char * const *av, void *priv)
{

	(void)cli;
	(void)av;
	(void)priv;
	/* XXX: Add selector mechanism at some point */
	vca_act = vca_acceptors[0];

	if (vca_act->name == NULL) {
		fprintf(stderr, "No acceptor in program\n");
		exit (2);
	}
	AZ(pipe(vca_pipes));
	vca_act->init();
	AZ(pthread_create(&vca_thread_acct, NULL, vca_acct, NULL));
	VSL(SLT_Debug, 0, "Acceptor is %s", vca_act->name);
}

static struct cli_proto vca_cmds[] = {
	{ CLI_SERVER_START,	ccf_start },
	{ NULL }
};

void
VCA_Init(void)
{

	CLI_AddFuncs(MASTER_CLI, vca_cmds);
}
