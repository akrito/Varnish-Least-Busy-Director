/*-
 * Copyright (c) 2006 Verdens Gang AS
 * Copyright (c) 2006 Linpro AS
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
 * THIS SOFTWARE IS PROVIDED BY AUTHOR AND CONTRIBUTORS ``AS IS'' AND
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
 * Initial implementation by Poul-Henning Kamp <phk@phk.freebsd.dk>
 *
 * $Id$
 */

#include <sys/uio.h>

#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "vsb.h"

#include "cli.h"
#include "cli_priv.h"
#include "cli_common.h"

void
cli_out(struct cli *cli, const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	if (cli != NULL)
		vsb_vprintf(cli->sb, fmt, ap);
	else
		vfprintf(stdout, fmt, ap);
	va_end(ap);
}

void
cli_result(struct cli *cli, unsigned res)
{

	if (cli != NULL)
		cli->result = res;
	else
		printf("CLI result = %d\n", res);
}


void
cli_param(struct cli *cli)
{

	cli_result(cli, CLIS_PARAM);
	cli_out(cli, "Parameter error, use \"help [command]\" for more info.\n");
}

int
cli_writeres(int fd, struct cli *cli)
{
	int i, l;
	struct iovec iov[3];
	char res[CLI_LINE0_LEN + 2];	/*
					 * NUL + one more so we can catch
					 * any misformats by snprintf
					 */

	assert(cli->result >= 100);
	assert(cli->result <= 999);
	i = snprintf(res, sizeof res,
	    "%-3d %-8d\n", cli->result, vsb_len(cli->sb));
	assert(i == CLI_LINE0_LEN);
	iov[0].iov_base = (void*)(uintptr_t)res;
	iov[1].iov_base = (void*)(uintptr_t)vsb_data(cli->sb);
	iov[2].iov_base = (void*)(uintptr_t)"\n";
	for (l = i = 0; i < 3; i++) {
		iov[i].iov_len = strlen(iov[i].iov_base);
		l += iov[i].iov_len;
	}
	i = writev(fd, iov, 3);
	return (i != l);
}

static int
read_tmo(int fd, char *ptr, unsigned len, double tmo)
{
	int i, j;
	struct pollfd pfd;

	pfd.fd = fd;
	pfd.events = POLLIN;
	i = poll(&pfd, 1, (int)(tmo * 1e3));
	if (i == 0) {
		errno = ETIMEDOUT;
		return (-1);
	}
	for (j = 0; len > 0; ) {
		i = read(fd, ptr, len);
		if (i < 0)
			return (i);
		if (i == 0)
			break;
		len -= i;
		ptr += i;
		j += i;
	}
	return (j);
}

int
cli_readres(int fd, unsigned *status, char **ptr, double tmo)
{
	char res[CLI_LINE0_LEN];	/* For NUL */
	int i, j;
	unsigned u, v;
	char *p;

	i = read_tmo(fd, res, CLI_LINE0_LEN, tmo);
	if (i != CLI_LINE0_LEN) {
		if (status != NULL)
			*status = CLIS_COMMS;
		if (ptr != NULL)
			*ptr = strdup("CLI communication error");
		return (1);
	}
	assert(i == CLI_LINE0_LEN);
	assert(res[3] == ' ');
	assert(res[CLI_LINE0_LEN - 1] == '\n');
	j = sscanf(res, "%u %u\n", &u, &v);
	assert(j == 2);
	if (status != NULL)
		*status = u;
	p = malloc(v + 1);
	assert(p != NULL);
	i = read_tmo(fd, p, v + 1, tmo);
	if (i < 0) {
		free(p);
		return (i);
	}
	assert(i == v + 1);
	assert(p[v] == '\n');
	p[v] = '\0';
	if (ptr == NULL)
		free(p);
	else
		*ptr = p;
	return (0);
}

/*--------------------------------------------------------------------*/

void
cli_func_ping(struct cli *cli, char **av, void *priv)
{
	time_t t;

	(void)priv;
	(void)av;
	t = time(NULL);
	cli_out(cli, "PONG %ld", t);
}
