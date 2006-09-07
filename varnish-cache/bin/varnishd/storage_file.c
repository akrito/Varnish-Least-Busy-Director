/*
 * $Id$
 *
 * Storage method based on mmap'ed file
 */

#include <sys/param.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/stat.h>

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

#ifndef MAP_NOCORE
#define MAP_NOCORE 0 /* XXX Linux */
#endif

#ifndef MAP_NOSYNC
#define MAP_NOSYNC 0 /* XXX Linux */
#endif

#define MINPAGES		128

#define NBUCKET			32	/* 32 * 4k = 128k (see fetch) */

/*--------------------------------------------------------------------*/

TAILQ_HEAD(smfhead, smf);

struct smf {
	unsigned		magic;
#define SMF_MAGIC		0x0927a8a0
	struct storage		s;
	struct smf_sc		*sc;

	int			alloc;
	time_t			age;

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
	pthread_mutex_t		mtx;
};

/*--------------------------------------------------------------------*/

static void
smf_calcsize(struct smf_sc *sc, const char *size, int newfile)
{
	uintmax_t l;
	unsigned bs;
	char suff[2];
	int i, expl;
	off_t o;
	struct statfs fsst;
	struct stat st;

	AZ(fstat(sc->fd, &st));
	AZ(fstatfs(sc->fd, &fsst));

	/* We use units of the larger of filesystem blocksize and pagesize */
	bs = sc->pagesize;
	if (bs < fsst.f_bsize)
		bs = fsst.f_bsize;

	xxxassert(S_ISREG(st.st_mode));

	i = sscanf(size, "%ju%1s", &l, suff); /* can return -1, 0, 1 or 2 */

	expl = i;
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

		o = l;
		if (o != l || o < 0) {
			fprintf(stderr,
			    "Warning: size reduced to system limit (off_t)\n");
			do {
				l >>= 1;
				o = l;
			} while (o != l || o < 0);
		}

		if (l < st.st_size) {
			AZ(ftruncate(sc->fd, l));
		} else if (l - st.st_size > fsst.f_bsize * fsst.f_bavail) {
			fprintf(stderr,
			    "Warning: size larger than filesystem free space,"
			    " reduced to 80%% of free space.\n");
			l = (fsst.f_bsize * fsst.f_bavail * 80) / 100;
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

	if (expl < 3 && sizeof(void *) == 4 && l > (1ULL << 31)) {
		fprintf(stderr,
		    "NB: Limiting size to 2GB on 32 bit architecture to"
		    " prevent running out of\naddress space."
		    "  Specifiy explicit size to override.\n"
		);
		l = 1ULL << 31;
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
		spec = "/tmp,50%";

	if (strchr(spec, ',') == NULL)
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
}

/*--------------------------------------------------------------------
 * Insert/Remove from correct freelist
 */

static void
insfree(struct smf_sc *sc, struct smf *sp)
{
	unsigned b, n;
	struct smf *sp2;

	assert(sp->alloc == 0);
	assert(sp->flist == NULL);
	b = sp->size / sc->pagesize;
	if (b >= NBUCKET)
		b = NBUCKET - 1;
	sp->flist = &sc->free[b];
	n = 0;
	TAILQ_FOREACH(sp2, sp->flist, status) {
		assert(sp2->alloc == 0);
		assert(sp2->flist == sp->flist);
		if (sp->age > sp2->age ||
		    (sp->age == sp2->age && sp->offset < sp2->offset)) {
			TAILQ_INSERT_BEFORE(sp2, sp, status);
			break;
		}
		n++;
	}
	if (sp2 == NULL)
		TAILQ_INSERT_TAIL(sp->flist, sp, status);
	VSL(SLT_Debug, 0, "FILE i %u %p %ju [%u]", b, sp, sp->size, n);
}

static void
remfree(struct smf_sc *sc, struct smf *sp)
{
	unsigned b;

	assert(sp->alloc == 0);
	assert(sp->flist != NULL);
	b = sp->size / sc->pagesize;
	if (b >= NBUCKET)
		b = NBUCKET - 1;
	assert(sp->flist == &sc->free[b]);
	TAILQ_REMOVE(sp->flist, sp, status);
	sp->flist = NULL;
	VSL(SLT_Debug, 0, "FILE r %u %p %ju", b, sp, sp->size);
}

/*--------------------------------------------------------------------
 * Allocate a range from the first free range that is large enough.
 */

static struct smf *
alloc_smf(struct smf_sc *sc, size_t bytes)
{
	struct smf *sp, *sp2;
	unsigned b;
	int n;

	b = bytes / sc->pagesize;
	if (b >= NBUCKET)
		b = NBUCKET - 1;
	n = 0;
	for (sp = NULL; b < NBUCKET; b++) {
		sp = TAILQ_FIRST(&sc->free[b]);
		if (sp != NULL)
			break;
		n++;
	}
	if (sp == NULL)
		return (sp);

	remfree(sc, sp);

	if (sp->size == bytes) {
		sp->alloc = 1;
		TAILQ_INSERT_TAIL(&sc->used, sp, status);
		VSL(SLT_Debug, 0, "FILE A %p %ju == %ju [%d]",
		    sp, (uintmax_t)sp->size, (uintmax_t)bytes, n);
		return (sp);
	}

	/* Split from front */
	sp2 = malloc(sizeof *sp2);
	XXXAN(sp2);
	VSL_stats->n_smf++;
	*sp2 = *sp;
	VSL(SLT_Debug, 0, "FILE A %p %ju > %ju [%d] %p",
	    sp, (uintmax_t)sp->size, (uintmax_t)bytes, n, sp2);

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
 * Free a range.  Attemt merge forward and backward, then sort into 
 * free list according to age.
 */

static void
free_smf(struct smf *sp)
{
	struct smf *sp2;
	struct smf_sc *sc = sp->sc;

	CHECK_OBJ_NOTNULL(sp, SMF_MAGIC);
	TAILQ_REMOVE(&sc->used, sp, status);
	assert(sp->alloc != 0);
	sp->alloc = 0;

	VSL(SLT_Debug, 0, "FILE F %p %ju", sp, sp->size);
	sp2 = TAILQ_NEXT(sp, order);
	if (sp2 != NULL &&
	    sp2->alloc == 0 &&
	    (sp2->ptr == sp->ptr + sp->size) &&
	    (sp2->offset == sp->offset + sp->size)) {
		sp->size += sp2->size;
		VSL(SLT_Debug, 0, "FILE CN %p -> %p %ju", sp2, sp, sp->size);
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
		VSL(SLT_Debug, 0, "FILE CP %p -> %p %ju", sp, sp2, sp2->size);
		sp2->age = sp->age;
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

	assert(bytes > 0);
	CHECK_OBJ_NOTNULL(sp, SMF_MAGIC);
	sp2 = malloc(sizeof *sp2);
	XXXAN(sp2);
	VSL_stats->n_smf++;
	*sp2 = *sp;

	sp2->size -= bytes;
	sp->size = bytes;
	sp2->ptr += bytes;
	sp2->offset += bytes;
	VSL(SLT_Debug, 0, "FILE T %p -> %p %ju %d", sp, sp2, sp2->size);
	TAILQ_INSERT_TAIL(&sc->used, sp2, status);
	TAILQ_INSERT_AFTER(&sc->order, sp, sp2, order);
	free_smf(sp2);
}

/*--------------------------------------------------------------------
 * Insert a newly created range as busy, then free it to do any collapses
 */

static void
new_smf(struct smf_sc *sc, unsigned char *ptr, off_t off, size_t len)
{
	struct smf *sp, *sp2;

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
	AZ(pthread_mutex_init(&sc->mtx, NULL));
}

/*--------------------------------------------------------------------*/

static struct storage *
smf_alloc(struct stevedore *st, size_t size)
{
	struct smf *smf;
	struct smf_sc *sc = st->priv;

	size += (sc->pagesize - 1);
	size &= ~(sc->pagesize - 1);
	LOCK(&sc->mtx);
	smf = alloc_smf(sc, size);
	CHECK_OBJ_NOTNULL(smf, SMF_MAGIC);
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
	if (size == 0) {
		/* XXX: this should not happen */
		return;
	}
	assert(size <= s->space);
	xxxassert(size > 0);	/* XXX: seen */
	CAST_OBJ_NOTNULL(smf, s->priv, SMF_MAGIC);
	assert(size <= smf->size);
	sc = smf->sc;
	size += (sc->pagesize - 1);
	size &= ~(sc->pagesize - 1);
	if (smf->size > size) {
		LOCK(&sc->mtx);
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
