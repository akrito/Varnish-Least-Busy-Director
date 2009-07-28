/*-
 * Copyright (c) 2006 Verdens Gang AS
 * Copyright (c) 2006-2008 Linpro AS
 * Copyright (c) 2009 Alex Kritikos
 * All rights reserved.
 *
 * Author: Alex Kritikos <alex.kritikos@gmail.com>
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
 * $Id: cache_dir_least_busy.c 3489 2008-12-21 18:33:44Z phk $
 *
 */

#include "config.h"

#include <sys/types.h>
#include <sys/socket.h>

#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "shmlog.h"
#include "cache.h"
#include "cache_backend.h"
#include "vrt.h"

/*--------------------------------------------------------------------*/

struct vdi_least_busy_host {
	struct backend		*backend;
};

struct vdi_least_busy {
	unsigned		magic;
#define VDI_LEAST_BUSY_MAGIC	0x3771ae24 /* FIXME */
	struct director		dir;

	struct vdi_least_busy_host	*hosts;
	unsigned		nhosts;
};

static struct vbe_conn *
vdi_least_busy_getfd(struct sess *sp)
{
  int b, i, n1, n2;
  struct vdi_least_busy *vs;
  struct vbe_conn *vbe;

  CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
  CHECK_OBJ_NOTNULL(sp->director, DIRECTOR_MAGIC);
  CAST_OBJ_NOTNULL(vs, sp->director->priv, VDI_LEAST_BUSY_MAGIC);


  /* Find the least-busy, healthy backend */
  n1 = -1;
  for (i = 0; i < vs->nhosts; i++) {
    if (vs->hosts[i].backend->healthy) {
      n2 = vs->hosts[i].backend->n_conn;
      if (n1 == -1 || n2 < n1) {
        b = i;
        n1 = n2;
      }
    }
  }
  vbe = VBE_GetVbe(sp, vs->hosts[i].backend);
  if (vbe != NULL)
    return (vbe);
  return (NULL);
}

static unsigned
vdi_least_busy_healthy(const struct sess *sp)
{
	struct vdi_least_busy *vs;
	int i;

	CHECK_OBJ_NOTNULL(sp, SESS_MAGIC);
	CHECK_OBJ_NOTNULL(sp->director, DIRECTOR_MAGIC);
	CAST_OBJ_NOTNULL(vs, sp->director->priv, VDI_LEAST_BUSY_MAGIC);

	for (i = 0; i < vs->nhosts; i++) {
		if (vs->hosts[i].backend->healthy)
			return 1;
	}
	return 0;
}

/*lint -e{818} not const-able */
static void
vdi_least_busy_fini(struct director *d)
{
	int i;
	struct vdi_least_busy *vs;
	struct vdi_least_busy_host *vh;

	CHECK_OBJ_NOTNULL(d, DIRECTOR_MAGIC);
	CAST_OBJ_NOTNULL(vs, d->priv, VDI_LEAST_BUSY_MAGIC);

	vh = vs->hosts;
	for (i = 0; i < vs->nhosts; i++, vh++)
		VBE_DropRef(vh->backend);
	free(vs->hosts);
	free(vs->dir.vcl_name);
	vs->dir.magic = 0;
	FREE_OBJ(vs);
}

void
VRT_init_dir_least_busy(struct cli *cli, struct director **bp,
    const struct vrt_dir_least_busy *t)
{
	struct vdi_least_busy *vs;
	const struct vrt_dir_least_busy_entry *te;
	struct vdi_least_busy_host *vh;
	int i;

	(void)cli;

	ALLOC_OBJ(vs, VDI_LEAST_BUSY_MAGIC);
	XXXAN(vs);
	vs->hosts = calloc(sizeof *vh, t->nmember);
	XXXAN(vs->hosts);

	vs->dir.magic = DIRECTOR_MAGIC;
	vs->dir.priv = vs;
	vs->dir.name = "least_busy";
	REPLACE(vs->dir.vcl_name, t->name);
	vs->dir.getfd = vdi_least_busy_getfd;
	vs->dir.fini = vdi_least_busy_fini;
	vs->dir.healthy = vdi_least_busy_healthy;

	vh = vs->hosts;
	te = t->members;
	for (i = 0; i < t->nmember; i++, vh++, te++)
		vh->backend = VBE_AddBackend(cli, te->host);
	vs->nhosts = t->nmember;

	*bp = &vs->dir;
}
