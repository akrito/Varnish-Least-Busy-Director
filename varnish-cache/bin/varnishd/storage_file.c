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
 * Storage method based on mmap'ed file
 */

#include <sys/param.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/stat.h>

#ifdef HAVE_SYS_MOUNT_H
#include <sys/mount.h>
#endif

#ifdef HAVE_SYS_VFS_H
#include <sys/vfs.h>
#endif

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef HAVE_ASPRINTF
#include "compat/asprintf.h"
#endif

#include "shmlog.h"
#include "cache.h"
#include "stevedore.h"

#ifndef MAP_NOCORE
#define MAP_NOCORE 0 /* XXX Linux */
#endif

#ifndef MAP_NOSYNC
#define MAP_NOSYNC 0 /* XXX Linux */
#endif

#define MINPAGES		128

/*
 * Number of buckets on free-list.
 *
 * Last bucket is "larger than" so choose number so that the second
 * to last bucket matches the 128k CHUNKSIZE in cache_fetch.c when
 * using the a 4K minimal page size
 */
#define NBUCKET			(128 / 4 + 1)

/*--------------------------------------------------------------------*/

TAILQ_HEAD(smfhead, smf);

struct smf {
	unsigned		magic;
#define SMF_MAGIC		0x0927a8a0
	struct storage		s;
	struct smf_sc		*sc;

	int			alloc;

	off_t			size;
	off_t			offset;
	unsigned char		*ptr;

	TAILQ_ENTRY(smf)	order;
	TAILQ_ENTRY(smf)	status;
	struct smfhead		*flist;
};

struct smf_sc {
	char			*filename;
	int			fd;
	unsigned		pagesize;
	uintmax_t		filesize;
	struct smfhead		order;
	struct smfhead		free[NBUCKET];
	struct smfhead		used;
	MTX			mtx;
};

/*--------------------------------------------------------------------*/

static void
smf_calcsize(struct smf_sc *sc, const char *size, int newfile)
{
	uintmax_t l;
	unsigned bs;
	char suff[2];
	int i, explicit;
	off_t o;
	struct stat st;

	AN(sc);
	AZ(fstat(sc->fd, &st));

#if defined(HAVE_SYS_MOUNT_H) || defined(HAVE_SYS_VFS_H)
	struct statfs fsst;
	AZ(fstatfs(sc->fd, &fsst));
#endif

	/* We use units of the larger of filesystem blocksize and pagesize */
	bs = sc->pagesize;
	if (bs < fsst.f_bsize)
		bs = fsst.f_bsize;

	xxxassert(S_ISREG(st.st_mode));

	i = sscanf(size, "%ju%1s", &l, suff); /* can return -1, 0, 1 or 2 */

	explicit = i;
	if (i == 0) {
		fprintf(stderr,
		    "Error: (-sfile) size \"%s\" not understood\n", size);
		exit (2);
	}

	if (i >= 1 && l == 0) {
		fprintf(stderr,
		    "Error: (-sfile) zero size not permitted\n");
		exit (2);
	}

	if (i == -1 && !newfile) /* Use the existing size of the file */
		l = st.st_size;

	/* We must have at least one block */
	if (l < bs) {
		if (i == -1) {
			fprintf(stderr,
			    "Info: (-sfile) default to 80%% size\n");
			l = 80;
			suff[0] = '%';
			i = 2;
		}

		if (i == 2) {
			if (suff[0] == 'k' || suff[0] == 'K')
				l *= 1024UL;
			else if (suff[0] == 'm' || suff[0] == 'M')
				l *= 1024UL * 1024UL;
			else if (suff[0] == 'g' || suff[0] == 'G')
				l *= 1024UL * 1024UL * 1024UL;
			else if (suff[0] == 't' || suff[0] == 'T')
				l *= (uintmax_t)(1024UL * 1024UL) *
				    (uintmax_t)(1024UL * 1024UL);
			else if (suff[0] == '%') {
				l *= fsst.f_bsize * fsst.f_bavail;
				l /= 100;
			}
		}

		/*
		 * This trickery wouldn't be necessary if X/Open would
		 * just add OFF_MAX to <limits.h>...
		 */
		o = l;
		if (o != l || o < 0) {
			do {
				l >>= 1;
				o = l;
			} while (o != l || o < 0);
			fprintf(stderr, "WARNING: storage file size reduced"
			    " to %ju due to system limitations\n", l);
		}

		if (l < st.st_size) {
			AZ(ftruncate(sc->fd, l));
		} else if (l - st.st_size > fsst.f_bsize * fsst.f_bavail) {
			l = ((uintmax_t)fsst.f_bsize * fsst.f_bavail * 80) / 100;
			fprintf(stderr, "WARNING: storage file size reduced"
			    " to %ju (80%% of available disk space)\n", l);
		}
	}

	/* round down to of filesystem blocksize or pagesize */
	l -= (l % bs);

	if (l < MINPAGES * (uintmax_t)sc->pagesize) {
		fprintf(stderr,
		    "Error: size too small, at least %ju needed\n",
		    (uintmax_t)MINPAGES * sc->pagesize);
		exit (2);
	}

	if (explicit < 3 && sizeof(void *) == 4 && l > INT32_MAX) {
		fprintf(stderr,
		    "NB: Limiting size to 2GB on 32 bit architecture to"
		    " prevent running out of\naddress space."
		    "  Specifiy explicit size to override.\n"
		);
		l = INT32_MAX;
		l -= (l % bs);
	}

	printf("file %s size %ju bytes (%ju fs-blocks, %ju pages)\n",
	    sc->filename, l, l / fsst.f_bsize, l / sc->pagesize);

	sc->filesize = l;
}

static void
smf_initfile(struct smf_sc *sc, const char *size, int newfile)
{
	smf_calcsize(sc, size, newfile);

	AZ(ftruncate(sc->fd, sc->filesize));

	/* XXX: force block allocation here or in open ? */
}

static void
smf_init(struct stevedore *parent, const char *spec)
{
	char *size;
	char *p, *q;
	struct stat st;
	struct smf_sc *sc;
	unsigned u;

	sc = calloc(sizeof *sc, 1);
	XXXAN(sc);
	TAILQ_INIT(&sc->order);
	for (u = 0; u < NBUCKET; u++)
		TAILQ_INIT(&sc->free[u]);
	TAILQ_INIT(&sc->used);
	sc->pagesize = getpagesize();

	parent->priv = sc;

	/* If no size specified, use 50% of filesystem free space */
	if (spec == NULL || *spec == '\0')
		asprintf(&p, ".,50%%");
	else if (strchr(spec, ',') == NULL)
		asprintf(&p, "%s,", spec);
	else
		p = strdup(spec);
	XXXAN(p);
	size = strchr(p, ',');
	XXXAN(size);

	*size++ = '\0';

	/* try to create a new file of this name */
	sc->fd = open(p, O_RDWR | O_CREAT | O_EXCL, 0600);
	if (sc->fd >= 0) {
		sc->filename = p;
		smf_initfile(sc, size, 1);
		return;
	}

	/* it must exist then */
	if (stat(p, &st)) {
		fprintf(stderr,
		    "Error: (-sfile) \"%s\" "
		    "does not exist and could not be created\n", p);
		exit (2);
	}

	/* and it should be a file or directory */
	if (!(S_ISREG(st.st_mode) || S_ISDIR(st.st_mode))) {
		fprintf(stderr,
		    "Error: (-sfile) \"%s\" "
		    "is neither file nor directory\n", p);
		exit (2);
	}

	if (S_ISREG(st.st_mode)) {
		sc->fd = open(p, O_RDWR);
		if (sc->fd < 0) {
			fprintf(stderr,
			    "Error: (-sfile) \"%s\" "
			    "could not open (%s)\n", p, strerror(errno));
			exit (2);
		}
		AZ(fstat(sc->fd, &st));
		if (!S_ISREG(st.st_mode)) {
			fprintf(stderr,
			    "Error: (-sfile) \"%s\" "
			    "was not a file after opening\n", p);
			exit (2);
		}
		sc->filename = p;
		smf_initfile(sc, size, 0);
		return;
	}


	asprintf(&q, "%s/varnish.XXXXXX", p);
	XXXAN(q);
	sc->fd = mkstemp(q);
	if (sc->fd < 0) {
		fprintf(stderr,
		    "Error: (-sfile) \"%s\" "
		    "mkstemp(%s) failed (%s)\n", p, q, strerror(errno));
		exit (2);
	}
	AZ(unlink(q));
	asprintf(&sc->filename, "%s (unlinked)", q);
	XXXAN(sc->filename);
	free(q);
	smf_initfile(sc, size, 1);
	free(p);
}

/*--------------------------------------------------------------------
 * Insert/Remove from correct freelist
 */

static void
insfree(struct smf_sc *sc, struct smf *sp)
{
	size_t b;
	struct smf *sp2;
	size_t ns;

	assert(sp->alloc == 0);
	assert(sp->flist == NULL);
	b = sp->size / sc->pagesize;
	if (b >= NBUCKET) {
		b = NBUCKET - 1;
		VSL_stats->n_smf_large++;
	} else {
		VSL_stats->n_smf_frag++;
	}
	sp->flist = &sc->free[b];
	ns = b * sc->pagesize;
	TAILQ_FOREACH(sp2, sp->flist, status) {
		assert(sp2->size >= ns);
		assert(sp2->alloc == 0);
		assert(sp2->flist == sp->flist);
		if (sp->offset < sp2->offset)
			break;
	}
	if (sp2 == NULL)
		TAILQ_INSERT_TAIL(sp->flist, sp, status);
	else
		TAILQ_INSERT_BEFORE(sp2, sp, status);
}

static void
remfree(struct smf_sc *sc, struct smf *sp)
{
	size_t b;

	assert(sp->alloc == 0);
	assert(sp->flist != NULL);
	b = sp->size / sc->pagesize;
	if (b >= NBUCKET) {
		b = NBUCKET - 1;
		VSL_stats->n_smf_large--;
	} else {
		VSL_stats->n_smf_frag--;
	}
	assert(sp->flist == &sc->free[b]);
	TAILQ_REMOVE(sp->flist, sp, status);
	sp->flist = NULL;
}

/*--------------------------------------------------------------------
 * Allocate a range from the first free range that is large enough.
 */

static struct smf *
alloc_smf(struct smf_sc *sc, size_t bytes)
{
	struct smf *sp, *sp2;
	size_t b;

	assert(!(bytes % sc->pagesize));
	b = bytes / sc->pagesize;
	if (b >= NBUCKET)
		b = NBUCKET - 1;
	for (sp = NULL; b < NBUCKET - 1; b++) {
		sp = TAILQ_FIRST(&sc->free[b]);
		if (sp != NULL)
			break;
	}
	if (sp == NULL) {
		TAILQ_FOREACH(sp, &sc->free[NBUCKET -1], status)
			if (sp->size >= bytes)
				break;
	}
	if (sp == NULL)
		return (sp);

	assert(sp->size >= bytes);
	remfree(sc, sp);

	if (sp->size == bytes) {
		sp->alloc = 1;
		TAILQ_INSERT_TAIL(&sc->used, sp, status);
		return (sp);
	}

	/* Split from front */
	sp2 = malloc(sizeof *sp2);
	XXXAN(sp2);
	VSL_stats->n_smf++;
	*sp2 = *sp;

	sp->offset += bytes;
	sp->ptr += bytes;
	sp->size -= bytes;

	sp2->size = bytes;
	sp2->alloc = 1;
	TAILQ_INSERT_BEFORE(sp, sp2, order);
	TAILQ_INSERT_TAIL(&sc->used, sp2, status);
	insfree(sc, sp);
	return (sp2);
}

/*--------------------------------------------------------------------
 * Free a range.  Attempt merge forward and backward, then sort into
 * free list according to age.
 */

static void
free_smf(struct smf *sp)
{
	struct smf *sp2;
	struct smf_sc *sc = sp->sc;

	CHECK_OBJ_NOTNULL(sp, SMF_MAGIC);
	assert(sp->alloc != 0);
	assert(sp->size > 0);
	assert(!(sp->size % sc->pagesize));
	TAILQ_REMOVE(&sc->used, sp, status);
	sp->alloc = 0;

	sp2 = TAILQ_NEXT(sp, order);
	if (sp2 != NULL &&
	    sp2->alloc == 0 &&
	    (sp2->ptr == sp->ptr + sp->size) &&
	    (sp2->offset == sp->offset + sp->size)) {
		sp->size += sp2->size;
		TAILQ_REMOVE(&sc->order, sp2, order);
		remfree(sc, sp2);
		free(sp2);
		VSL_stats->n_smf--;
	}

	sp2 = TAILQ_PREV(sp, smfhead, order);
	if (sp2 != NULL &&
	    sp2->alloc == 0 &&
	    (sp->ptr == sp2->ptr + sp2->size) &&
	    (sp->offset == sp2->offset + sp2->size)) {
		remfree(sc, sp2);
		sp2->size += sp->size;
		TAILQ_REMOVE(&sc->order, sp, order);
		free(sp);
		VSL_stats->n_smf--;
		sp = sp2;
	}

	insfree(sc, sp);
}

/*--------------------------------------------------------------------
 * Trim the tail of a range.
 */

static void
trim_smf(struct smf *sp, size_t bytes)
{
	struct smf *sp2;
	struct smf_sc *sc = sp->sc;

	assert(sp->alloc != 0);
	assert(bytes > 0);
	assert(bytes < sp->size);
	assert(!(bytes % sc->pagesize));
	assert(!(sp->size % sc->pagesize));
	CHECK_OBJ_NOTNULL(sp, SMF_MAGIC);
	sp2 = malloc(sizeof *sp2);
	XXXAN(sp2);
	VSL_stats->n_smf++;
	*sp2 = *sp;

	sp2->size -= bytes;
	sp->size = bytes;
	sp2->ptr += bytes;
	sp2->offset += bytes;
	TAILQ_INSERT_AFTER(&sc->order, sp, sp2, order);
	TAILQ_INSERT_TAIL(&sc->used, sp2, status);
	free_smf(sp2);
}

/*--------------------------------------------------------------------
 * Insert a newly created range as busy, then free it to do any collapses
 */

static void
new_smf(struct smf_sc *sc, unsigned char *ptr, off_t off, size_t len)
{
	struct smf *sp, *sp2;

	assert(!(len % sc->pagesize));
	sp = calloc(sizeof *sp, 1);
	XXXAN(sp);
	sp->magic = SMF_MAGIC;
	sp->s.magic = STORAGE_MAGIC;
	VSL_stats->n_smf++;

	sp->sc = sc;
	sp->size = len;
	sp->ptr = ptr;
	sp->offset = off;
	sp->alloc = 1;

	TAILQ_FOREACH(sp2, &sc->order, order) {
		if (sp->ptr < sp2->ptr) {
			TAILQ_INSERT_BEFORE(sp2, sp, order);
			break;
		}
	}
	if (sp2 == NULL)
		TAILQ_INSERT_TAIL(&sc->order, sp, order);

	TAILQ_INSERT_HEAD(&sc->used, sp, status);

	free_smf(sp);
}

/*--------------------------------------------------------------------*/

/*
 * XXX: This may be too aggressive and soak up too much address room.
 * XXX: On the other hand, the user, directly or implicitly asked us to
 * XXX: use this much storage, so we should make a decent effort.
 * XXX: worst case (I think), malloc will fail.
 */

static void
smf_open_chunk(struct smf_sc *sc, off_t sz, off_t off, off_t *fail, off_t *sum)
{
	void *p;
	off_t h;

	assert(sz != 0);
	assert(!(sz % sc->pagesize));

	if (*fail < (uintmax_t)sc->pagesize * MINPAGES)
		return;

	if (sz > 0 && sz < *fail && sz < SIZE_MAX) {
		p = mmap(NULL, sz, PROT_READ|PROT_WRITE,
		    MAP_NOCORE | MAP_NOSYNC | MAP_SHARED, sc->fd, off);
		if (p != MAP_FAILED) {
			(*sum) += sz;
			new_smf(sc, p, off, sz);
			return;
		}
	}

	if (sz < *fail)
		*fail = sz;

	h = sz / 2;
	if (h > SIZE_MAX)
		h = SIZE_MAX;
	h -= (h % sc->pagesize);

	smf_open_chunk(sc, h, off, fail, sum);
	smf_open_chunk(sc, sz - h, off + h, fail, sum);
}

static void
smf_open(struct stevedore *st)
{
	struct smf_sc *sc;
	off_t fail = 1 << 30;	/* XXX: where is OFF_T_MAX ? */
	off_t sum = 0;

	sc = st->priv;

	smf_open_chunk(sc, sc->filesize, 0, &fail, &sum);
	printf("managed to mmap %ju bytes of %ju\n",
	    (uintmax_t)sum, sc->filesize);

	/* XXX */
	if (sum < MINPAGES * (uintmax_t)getpagesize())
		exit (2);
	MTX_INIT(&sc->mtx);

	VSL_stats->sm_bfree += sc->filesize;
}

/*--------------------------------------------------------------------*/

static struct storage *
smf_alloc(struct stevedore *st, size_t size)
{
	struct smf *smf;
	struct smf_sc *sc = st->priv;

	assert(size > 0);
	size += (sc->pagesize - 1);
	size &= ~(sc->pagesize - 1);
	LOCK(&sc->mtx);
	VSL_stats->sm_nreq++;
	smf = alloc_smf(sc, size);
	if (smf == NULL) {
		UNLOCK(&sc->mtx);
		return (NULL);
	}
	CHECK_OBJ_NOTNULL(smf, SMF_MAGIC);
	VSL_stats->sm_nobj++;
	VSL_stats->sm_balloc += smf->size;
	VSL_stats->sm_bfree -= smf->size;
	UNLOCK(&sc->mtx);
	XXXAN(smf);
	assert(smf->size == size);
	smf->s.space = size;
	smf->s.priv = smf;
	smf->s.ptr = smf->ptr;
	smf->s.len = 0;
	smf->s.stevedore = st;
	smf->s.fd = smf->sc->fd;
	smf->s.where = smf->offset;
	CHECK_OBJ_NOTNULL(&smf->s, STORAGE_MAGIC);
	return (&smf->s);
}

/*--------------------------------------------------------------------*/

static void
smf_trim(struct storage *s, size_t size)
{
	struct smf *smf;
	struct smf_sc *sc;

	CHECK_OBJ_NOTNULL(s, STORAGE_MAGIC);
	assert(size > 0);
	assert(size <= s->space);
	xxxassert(size > 0);	/* XXX: seen */
	CAST_OBJ_NOTNULL(smf, s->priv, SMF_MAGIC);
	assert(size <= smf->size);
	sc = smf->sc;
	size += (sc->pagesize - 1);
	size &= ~(sc->pagesize - 1);
	if (smf->size > size) {
		LOCK(&sc->mtx);
		VSL_stats->sm_balloc -= (smf->size - size);
		VSL_stats->sm_bfree += (smf->size - size);
		trim_smf(smf, size);
		assert(smf->size == size);
		UNLOCK(&sc->mtx);
		smf->s.space = size;
	}
}

/*--------------------------------------------------------------------*/

static void
smf_free(struct storage *s)
{
	struct smf *smf;
	struct smf_sc *sc;

	CHECK_OBJ_NOTNULL(s, STORAGE_MAGIC);
	CAST_OBJ_NOTNULL(smf, s->priv, SMF_MAGIC);
	sc = smf->sc;
	LOCK(&sc->mtx);
	VSL_stats->sm_nobj--;
	VSL_stats->sm_balloc -= smf->size;
	VSL_stats->sm_bfree += smf->size;
	free_smf(smf);
	UNLOCK(&sc->mtx);
}

/*--------------------------------------------------------------------*/

struct stevedore smf_stevedore = {
	.name =		"file",
	.init =		smf_init,
	.open =		smf_open,
	.alloc =	smf_alloc,
	.trim =		smf_trim,
	.free =		smf_free,
};

#ifdef INCLUDE_TEST_DRIVER

void vca_flush(struct sess *sp) {}
void vca_close_session(struct sess *sp, const char *why) {}

#define N	100
#define M	(128*1024)

struct storage *s[N];

static void
dumpit(void)
{
	struct smf_sc *sc = smf_stevedore.priv;
	struct smf *s;

	return (0);
	printf("----------------\n");
	printf("Order:\n");
	TAILQ_FOREACH(s, &sc->order, order) {
		printf("%10p %12ju %12ju %12ju\n",
		    s, s->offset, s->size, s->offset + s->size);
	}
	printf("Used:\n");
	TAILQ_FOREACH(s, &sc->used, status) {
		printf("%10p %12ju %12ju %12ju\n",
		    s, s->offset, s->size, s->offset + s->size);
	}
	printf("Free:\n");
	TAILQ_FOREACH(s, &sc->free, status) {
		printf("%10p %12ju %12ju %12ju\n",
		    s, s->offset, s->size, s->offset + s->size);
	}
	printf("================\n");
}

int
main(int argc, char **argv)
{
	int i, j;

	setbuf(stdout, NULL);
	smf_init(&smf_stevedore, "");
	smf_open(&smf_stevedore);
	while (1) {
		dumpit();
		i = random() % N;
		do
			j = random() % M;
		while (j == 0);
		if (s[i] == NULL) {
			s[i] = smf_alloc(&smf_stevedore, j);
			printf("A %10p %12d\n", s[i], j);
		} else if (j < s[i]->space) {
			smf_trim(s[i], j);
			printf("T %10p %12d\n", s[i], j);
		} else {
			smf_free(s[i]);
			printf("D %10p\n", s[i]);
			s[i] = NULL;
		}
	}
}

#endif /* INCLUDE_TEST_DRIVER */
