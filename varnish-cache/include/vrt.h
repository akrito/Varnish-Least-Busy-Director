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
 * Runtime support for compiled VCL programs.
 *
 * XXX: When this file is changed, lib/libvcl/vcc_gen_fixed_token.tcl
 * XXX: *MUST* be rerun.
 */

struct sess;
struct vsb;
struct cli;
struct director;
struct VCL_conf;
struct sockaddr;

/*
 * A backend is a host+port somewhere on the network
 */
struct vrt_backend {
	const char	*portname;
	const char	*hostname;
	const char	*ident;
};

/*
 * A director with a predictable reply
 */

struct vrt_dir_simple {
	const char				*ident;
	const char				*name;
	const struct vrt_backend		*host;
};

/*
 * A director with an unpredictable reply
 */

struct vrt_dir_random_entry {
	const struct vrt_backend		*host;
	double					weight;
};

struct vrt_dir_random {
	const char 				*ident;
	const char 				*name;
	unsigned 				nmember;
	const struct vrt_dir_random_entry	*members;
};

/*
 * other stuff.
 * XXX: document when bored
 */

struct vrt_ref {
	unsigned	source;
	unsigned	offset;
	unsigned	line;
	unsigned	pos;
	unsigned	count;
	const char	*token;
};

struct vrt_acl {
	unsigned char	not;
	unsigned char	mask;
	unsigned char	paren;
	const char	*name;
	const char	*desc;
	void		*priv;
};

/* ACL related */
int VRT_acl_match(const struct sess *, struct sockaddr *, const char *, const struct vrt_acl *);
void VRT_acl_init(struct vrt_acl *);
void VRT_acl_fini(struct vrt_acl *);

/* Regexp related */
void VRT_re_init(void **, const char *, int sub);
void VRT_re_fini(void *);
int VRT_re_match(const char *, void *re);
int VRT_re_test(struct vsb *, const char *, int sub);
const char *VRT_regsub(const struct sess *sp, const char *, void *, const char *);

void VRT_purge(const char *, int hash);

void VRT_count(const struct sess *, unsigned);
int VRT_rewrite(const char *, const char *);
void VRT_error(struct sess *, unsigned, const char *);
int VRT_switch_config(const char *);

enum gethdr_e { HDR_REQ, HDR_RESP, HDR_OBJ, HDR_BEREQ };
char *VRT_GetHdr(const struct sess *, enum gethdr_e where, const char *);
void VRT_SetHdr(const struct sess *, enum gethdr_e where, const char *, const char *, ...);
void VRT_handling(struct sess *sp, unsigned hand);

/* Simple stuff */
int VRT_strcmp(const char *s1, const char *s2);

void VRT_ESI(struct sess *sp);
void VRT_Rollback(struct sess *sp);

/* Backend related */
void VRT_init_dir_simple(struct cli *, struct director **, const struct vrt_dir_simple *);
void VRT_init_dir_random(struct cli *, struct director **, const struct vrt_dir_random *);
void VRT_fini_dir(struct cli *, struct director *);

char *VRT_IP_string(const struct sess *sp, const struct sockaddr *sa);
char *VRT_int_string(const struct sess *sp, int);

#define VRT_done(sp, hand)			\
	do {					\
		VRT_handling(sp, hand);		\
		return (1);			\
	} while (0)
