/*-
 * Copyright (c) 2007-2008 Linpro AS
 * All rights reserved.
 *
 * Author: Dag-Erling Smørgav <des@des.no>
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

#include "config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cache.h"
#include "stevedore.h"

extern struct stevedore sma_stevedore;
extern struct stevedore smf_stevedore;

static VTAILQ_HEAD(, stevedore)	stevedores =
    VTAILQ_HEAD_INITIALIZER(stevedores);

static struct stevedore * volatile stv_next;

struct storage *
STV_alloc(struct sess *sp, size_t size)
{
	struct storage *st;
	struct stevedore *stv;

	for (;;) {

		/* pick a stevedore and bump the head along */
		stv = VTAILQ_NEXT(stv_next, list);
		if (stv == NULL)
			stv = VTAILQ_FIRST(&stevedores);
		AN(stv);

		 /* XXX: only safe as long as pointer writes are atomic */
		stv_next = stv;

		/* try to allocate from it */
		st = stv->alloc(stv, size);
		if (st != NULL)
			break;

		/* no luck; try to free some space and keep trying */
		if (EXP_NukeOne(sp) == -1)
			break;
	}
	CHECK_OBJ_NOTNULL(st, STORAGE_MAGIC);
	return (st);
}

void
STV_trim(const struct storage *st, size_t size)
{

	CHECK_OBJ_NOTNULL(st, STORAGE_MAGIC);
	AN(st->stevedore);
	if (st->stevedore->trim)
		st->stevedore->trim(st, size);
}

void
STV_free(const struct storage *st)
{

	CHECK_OBJ_NOTNULL(st, STORAGE_MAGIC);
	AN(st->stevedore);
	AN(st->stevedore->free);
	st->stevedore->free(st);
}

static int
cmp_storage(const struct stevedore *s, const char *p, const char *q)
{
	unsigned u;

	u = pdiff(p, q);
	if (strlen(s->name) != u)
		return (1);
	if (strncmp(s->name, p, u))
		return (1);
	return (0);
}

void
STV_add(const char *spec)
{
	const char *p, *q;
	struct stevedore *stv;

	p = strchr(spec, ',');
	if (p == NULL)
		q = p = strchr(spec, '\0');
	else
		q = p + 1;
	xxxassert(p != NULL);
	xxxassert(q != NULL);

	stv = malloc(sizeof *stv);
	AN(stv);

	if (!cmp_storage(&sma_stevedore, spec, p)) {
		*stv = sma_stevedore;
	} else if (!cmp_storage(&smf_stevedore, spec, p)) {
		*stv = smf_stevedore;
	} else {
		fprintf(stderr, "Unknown storage method \"%.*s\"\n",
		    (int)(p - spec), spec);
		exit (2);
	}
	if (stv->init != NULL)
		stv->init(stv, q);

	VTAILQ_INSERT_TAIL(&stevedores, stv, list);

	if (!stv_next)
		stv_next = VTAILQ_FIRST(&stevedores);
}

void
STV_open(void)
{
	struct stevedore *stv;

	VTAILQ_FOREACH(stv, &stevedores, list) {
		if (stv->open != NULL)
			stv->open(stv);
	}
}
