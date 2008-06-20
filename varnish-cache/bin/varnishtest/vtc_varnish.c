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


#include <stdio.h>

#include <stdio.h>
#include <ctype.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <pthread.h>
#include <signal.h>

#include <sys/types.h>
#include <sys/wait.h>
#include <sys/socket.h>


#include "vqueue.h"
#include "miniobj.h"
#include "libvarnish.h"
#include "cli.h"
#include "cli_common.h"
#include "vss.h"
#include "vsb.h"

#include "vtc.h"

struct varnish {
	unsigned		magic;
#define VARNISH_MAGIC		0x208cd8e3
	char			*name;
	struct vtclog		*vl;
	VTAILQ_ENTRY(varnish)	list;

	const char		*args;
	int			fds[4];
	pid_t			pid;
	const char		*telnet;
	const char		*accept;

	pthread_t		tp;

	int			cli_fd;
	int			vcl_nbr;
};

static VTAILQ_HEAD(, varnish)	varnishes =
    VTAILQ_HEAD_INITIALIZER(varnishes);

/**********************************************************************
 * Ask a question over CLI
 */

static enum cli_status_e
varnish_ask_cli(const struct varnish *v, const char *cmd, char **repl)
{
	int i;
	unsigned retval;
	char *r;

	vtc_dump(v->vl, 4, "CLI TX", cmd);
	i = write(v->cli_fd, cmd, strlen(cmd));
	assert(i == strlen(cmd));
	i = write(v->cli_fd, "\n", 1);
	assert(i == 1);
	i = cli_readres(v->cli_fd, &retval, &r, 1000);
	assert(i == 0);
	vtc_log(v->vl, 3, "CLI %u <%s>", retval, cmd);
	vtc_dump(v->vl, 4, "CLI RX", r);
	if (repl != NULL)
		*repl = r;
	else
		free(r);
	return ((enum cli_status_e)retval);
}

static void
varnish_cli_encode(struct vsb *vsb, const char *str)
{

	for (; *str != '\0'; str++) {
		switch (*str) {
		case '\\':
		case '"':
			vsb_printf(vsb, "\\%c", *str); break;
		case '\n':
			vsb_printf(vsb, "\\n"); break;
		case '\t':
			vsb_printf(vsb, "\\t"); break;
		default:
			if (isgraph(*str) || *str == ' ')
				vsb_putc(vsb, *str);
			else
				vsb_printf(vsb, "\\x%02x", *str);
		}
	}
}

/**********************************************************************
 * Allocate and initialize a varnish
 */

static struct varnish *
varnish_new(char *name)
{
	struct varnish *v;

	ALLOC_OBJ(v, VARNISH_MAGIC);
	AN(v);
	v->name = name;
	v->vl = vtc_logopen(name);
	AN(v->vl);
	if (*name != 'v') {
		vtc_log(v->vl, 0, "Varnish name must start with 'v'");
		exit (1);
	}

	v->args = "";
	v->telnet = ":9001";
	v->accept = ":9081";
	v->cli_fd = -1;
	VTAILQ_INSERT_TAIL(&varnishes, v, list);
	return (v);
}

/**********************************************************************
 * Varnish listener
 */

static void *
varnish_thread(void *priv)
{
	struct varnish *v;
	char buf[BUFSIZ];
	int i;

	CAST_OBJ_NOTNULL(v, priv, VARNISH_MAGIC);
	while (1) {
		i = read(v->fds[0], buf, sizeof buf - 1);
		if (i <= 0)
			break;
		buf[i] = '\0';
		vtc_dump(v->vl, 4, "debug", buf);
	}
	return (NULL);
}

/**********************************************************************
 * Launch a Varnish
 */

static void
varnish_launch(struct varnish *v)
{
	struct vsb *vsb;
	int i;

	vtc_log(v->vl, 2, "Launch");
	vsb = vsb_newauto();
	AN(vsb);
	vsb_printf(vsb, "cd ../varnishd &&");
	vsb_printf(vsb, " ./varnishd -d -d -n %s", v->name);
	vsb_printf(vsb, " -a %s -T %s", v->accept, v->telnet);
	vsb_printf(vsb, " %s", v->args);
	vsb_finish(vsb);
	AZ(vsb_overflowed(vsb));
	vtc_log(v->vl, 3, "CMD: %s", vsb_data(vsb));
	AZ(pipe(&v->fds[0]));
	AZ(pipe(&v->fds[2]));
	v->pid = fork();
	assert(v->pid >= 0);
	if (v->pid == 0) {
		assert(dup2(v->fds[0], 0) == 0);
		assert(dup2(v->fds[3], 1) == 1);
		assert(dup2(1, 2) == 2);
		AZ(close(v->fds[0]));
		AZ(close(v->fds[1]));
		AZ(close(v->fds[2]));
		AZ(close(v->fds[3]));
		AZ(execl("/bin/sh", "/bin/sh", "-c", vsb_data(vsb), NULL));
		exit(1);
	}
	AZ(close(v->fds[0]));
	AZ(close(v->fds[3]));
	v->fds[0] = v->fds[2];
	v->fds[2] = v->fds[3] = -1;
	vsb_delete(vsb);
	AZ(pthread_create(&v->tp, NULL, varnish_thread, v));

	vtc_log(v->vl, 3, "opening CLI connection");
	for (i = 0; i < 10; i++) {
		(void)usleep(200000);
		v->cli_fd = VSS_open(v->telnet);
		if (v->cli_fd >= 0)
			break;
	}
	if (v->cli_fd < 0) {
		vtc_log(v->vl, 0, "FAIL no CLI connection");
		(void)kill(v->pid, SIGKILL);
		exit (1);
	}
	vtc_log(v->vl, 3, "CLI connection fd = %d", v->cli_fd);
	assert(v->cli_fd >= 0);
}

/**********************************************************************
 * Start a Varnish
 */

static void
varnish_start(struct varnish *v)
{
	enum cli_status_e u;

	if (v->cli_fd < 0)
		varnish_launch(v);
	vtc_log(v->vl, 2, "Start");
	u = varnish_ask_cli(v, "start", NULL);
	assert(u == CLIS_OK);
	u = varnish_ask_cli(v, "debug.xid 1000", NULL);
	assert(u == CLIS_OK);
}

/**********************************************************************
 * Stop a Varnish
 */

static void
varnish_stop(struct varnish *v)
{

	if (v->cli_fd < 0)
		varnish_launch(v);
	vtc_log(v->vl, 2, "Stop");
	(void)varnish_ask_cli(v, "stop", NULL);
}

/**********************************************************************
 * Wait for a Varnish
 */

static void
varnish_wait(struct varnish *v)
{
	void *p;
	int status, r;

	if (v->cli_fd < 0)
		return;
	varnish_stop(v);
	vtc_log(v->vl, 2, "Wait");
	AZ(close(v->cli_fd));
	v->cli_fd = -1;

	AZ(close(v->fds[1]));

	AZ(pthread_join(v->tp, &p));
	AZ(close(v->fds[0]));
	r = wait4(v->pid, &status, 0, NULL);
	vtc_log(v->vl, 2, "R %d Status: %04x", r, status);
}

/**********************************************************************
 * Ask a CLI question
 */

static void
varnish_cli(struct varnish *v, const char *cli)
{
	enum cli_status_e u;

	if (v->cli_fd < 0)
		varnish_launch(v);
	u = varnish_ask_cli(v, cli, NULL);
	vtc_log(v->vl, 2, "CLI %03u <%s>", u, cli);
}

/**********************************************************************
 * Load a VCL program
 */

static void
varnish_vcl(struct varnish *v, const char *vcl)
{
	struct vsb *vsb;
	enum cli_status_e u;

	if (v->cli_fd < 0)
		varnish_launch(v);
	vsb = vsb_newauto();
	AN(vsb);

	v->vcl_nbr++;
	vsb_printf(vsb, "vcl.inline vcl%d \"", v->vcl_nbr);
	for (vcl++; vcl[1] != '\0'; vcl++) {
		switch (*vcl) {
		case '\\':
		case '"':
			vsb_printf(vsb, "\\%c", *vcl); break;
		case '\n':
			vsb_printf(vsb, "\\n"); break;
		case '\t':
			vsb_printf(vsb, "\\t"); break;
		default:
			if (isgraph(*vcl) || *vcl == ' ')
				vsb_putc(vsb, *vcl);
			else
				vsb_printf(vsb, "\\x%02x", *vcl);
		}
	}
	vsb_printf(vsb, "\"", *vcl);
	vsb_finish(vsb);
	AZ(vsb_overflowed(vsb));

	u = varnish_ask_cli(v, vsb_data(vsb), NULL);
	assert(u == CLIS_OK);
	vsb_clear(vsb);
	vsb_printf(vsb, "vcl.use vcl%d", v->vcl_nbr);
	vsb_finish(vsb);
	AZ(vsb_overflowed(vsb));
	u = varnish_ask_cli(v, vsb_data(vsb), NULL);
	assert(u == CLIS_OK);
	vsb_delete(vsb);
}

/**********************************************************************
 * Load a VCL program prefixed by backend decls for our servers
 */

static void
varnish_vclbackend(struct varnish *v, char *vcl)
{
	struct vsb *vsb, *vsb2;
	char *p;
	enum cli_status_e u;

	if (v->cli_fd < 0)
		varnish_launch(v);
	vsb = vsb_newauto();
	AN(vsb);

	vsb2 = vsb_newauto();
	AN(vsb2);

	cmd_server_genvcl(vsb2);
	vsb_finish(vsb2);
	AZ(vsb_overflowed(vsb2));

	v->vcl_nbr++;
	vsb_printf(vsb, "vcl.inline vcl%d \"", v->vcl_nbr);

	varnish_cli_encode(vsb, vsb_data(vsb2));

	if (*vcl == '{') {
		p = strchr(++vcl, '\0');
		if (p > vcl && p[-1] == '}')
			p[-1] = '\0';
	}
	varnish_cli_encode(vsb, vcl);

	vsb_printf(vsb, "\"", *vcl);
	vsb_finish(vsb);
	AZ(vsb_overflowed(vsb));

	u = varnish_ask_cli(v, vsb_data(vsb), NULL);
	assert(u == CLIS_OK);
	vsb_clear(vsb);
	vsb_printf(vsb, "vcl.use vcl%d", v->vcl_nbr);
	vsb_finish(vsb);
	AZ(vsb_overflowed(vsb));
	u = varnish_ask_cli(v, vsb_data(vsb), NULL);
	assert(u == CLIS_OK);
	vsb_delete(vsb);
	vsb_delete(vsb2);
}

/**********************************************************************
 * Varnish server cmd dispatch
 */

void
cmd_varnish(char **av, void *priv)
{
	struct varnish *v, *v2;

	(void)priv;

	if (av == NULL) {
		/* Reset and free */
		VTAILQ_FOREACH_SAFE(v, &varnishes, list, v2) {
			if (v->cli_fd >= 0)
				varnish_wait(v);
			VTAILQ_REMOVE(&varnishes, v, list);
			FREE_OBJ(v);
			/* XXX: MEMLEAK */
		}
		return;
	}

	assert(!strcmp(av[0], "varnish"));
	av++;

	VTAILQ_FOREACH(v, &varnishes, list)
		if (!strcmp(v->name, av[0]))
			break;
	if (v == NULL) 
		v = varnish_new(av[0]);
	av++;

	for (; *av != NULL; av++) {
		if (!strcmp(*av, "-telnet")) {
			v->telnet = av[1];
			av++;
			continue;
		}
		if (!strcmp(*av, "-accept")) {
			v->accept = av[1];
			av++;
			continue;
		}
		if (!strcmp(*av, "-arg")) {
			v->args = av[1];
			av++;
			continue;
		}
		if (!strcmp(*av, "-cli")) {
			varnish_cli(v, av[1]);
			av++;
			continue;
		}
		if (!strcmp(*av, "-launch")) {
			varnish_launch(v);
			continue;
		}
		if (!strcmp(*av, "-start")) {
			varnish_start(v);
			continue;
		}
		if (!strcmp(*av, "-vcl+backend")) {
			varnish_vclbackend(v, av[1]);
			av++;
			continue;
		}
		if (!strcmp(*av, "-vcl")) {
			varnish_vcl(v, av[1]);
			av++;
			continue;
		}
		if (!strcmp(*av, "-stop")) {
			varnish_stop(v);
			continue;
		}
		if (!strcmp(*av, "-wait")) {
			varnish_wait(v);
			continue;
		}
		vtc_log(v->vl, 0, "Unknown varnish argument: %s", *av);
		exit (1);
	}
}
