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
 * Runtime support for compiled VCL programs.
 *
 * XXX: When this file is changed, lib/libvcl/vcc_gen_fixed_token.tcl
 * XXX: *MUST* be rerun.
 */

struct sess;
struct vsb;
struct backend;
struct VCL_conf;
struct sockaddr;

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
int VRT_acl_match(struct sess *, struct sockaddr *, const char *, struct vrt_acl *);
void VRT_acl_init(struct vrt_acl *);
void VRT_acl_fini(struct vrt_acl *);

/* Regexp related */
void VRT_re_init(void **, const char *, int sub);
void VRT_re_fini(void *);
int VRT_re_match(const char *, void *re);
int VRT_re_test(struct vsb *, const char *, int sub);
const char *VRT_regsub(struct sess *sp, const char *, void *, const char *);

void VRT_purge(const char *, int hash);

void VRT_count(struct sess *, unsigned);
int VRT_rewrite(const char *, const char *);
void VRT_error(struct sess *, unsigned, const char *);
int VRT_switch_config(const char *);

enum gethdr_e { HDR_REQ, HDR_RESP, HDR_OBJ, HDR_BEREQ };
char *VRT_GetHdr(struct sess *, enum gethdr_e where, const char *);
void VRT_SetHdr(struct sess *, enum gethdr_e where, const char *, const char *, ...);
void VRT_handling(struct sess *sp, unsigned hand);

/* Backend related */
void VRT_set_backend_name(struct backend *, const char *);
void VRT_alloc_backends(struct VCL_conf *cp);
void VRT_free_backends(struct VCL_conf *cp);
void VRT_fini_backend(struct backend *be);

char *VRT_IP_string(struct sess *sp, struct sockaddr *sa);
char *VRT_int_string(struct sess *sp, int);

#define VRT_done(sp, hand)			\
	do {					\
		VRT_handling(sp, hand);		\
		return (1);			\
	} while (0)
