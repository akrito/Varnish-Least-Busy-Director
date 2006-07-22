/*
 * $Id$
 */

struct stevedore;
struct sess;
struct iovec;

typedef void storage_init_f(struct stevedore *, const char *spec);
typedef void storage_open_f(struct stevedore *);
typedef struct storage *storage_alloc_f(struct stevedore *, size_t size);
typedef void storage_trim_f(struct storage *, size_t size);
typedef void storage_free_f(struct storage *);
typedef void storage_send_f(struct storage *, struct sess *);

struct stevedore {
	const char		*name;
	storage_init_f		*init;	/* called by mgt process */
	storage_open_f		*open;	/* called by cache process */
	storage_alloc_f		*alloc;
	storage_trim_f		*trim;
	storage_free_f		*free;
	storage_send_f		*send;

	/* private fields */
	void			*priv;
};
