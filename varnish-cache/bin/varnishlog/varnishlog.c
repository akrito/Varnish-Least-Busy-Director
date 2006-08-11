/*
 * $Id$
 *
 * Log tailer for Varnish
 */

#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

#include "compat/vis.h"

#include "vsb.h"

#include "libvarnish.h"
#include "shmlog.h"
#include "varnishapi.h"

static int	bflag, cflag;

/* Ordering-----------------------------------------------------------*/

static struct vsb	*ob[65536];
static unsigned char	invcl[65536];

static void
clean_order(void)
{
	unsigned u;

printf("Clean\n");
	for (u = 0; u < 65536; u++) {
		if (ob[u] == NULL)
			continue;
		vsb_finish(ob[u]);
		if (vsb_len(ob[u]))
			printf("%s\n", vsb_data(ob[u]));
		vsb_clear(ob[u]);
	}
}

static int 
h_order(void *priv, unsigned tag, unsigned fd, unsigned len, unsigned spec, const char *ptr)
{

	(void)priv;

	if (!(spec & (VSL_S_CLIENT|VSL_S_BACKEND))) {
		VSL_H_Print(stdout, tag, fd, len, spec, ptr);
		return (0);
	}
	if (ob[fd] == NULL) {
		ob[fd] = vsb_new(NULL, NULL, 0, VSB_AUTOEXTEND);
		assert(ob[fd] != NULL);
	}
	switch (tag) {
	case SLT_VCL_call:
		invcl[fd] = 1;
		vsb_printf(ob[fd], "%5d %-12s %c %.*s",
		    fd, VSL_tags[tag],
		    ((spec & VSL_S_CLIENT) ? 'c' : \
		    (spec & VSL_S_BACKEND) ? 'b' : ' '),
		    len, ptr);
		return (0);
	case SLT_VCL_trace:
	case SLT_VCL_return:
		if (invcl[fd]) {
			vsb_cat(ob[fd], " ");
			vsb_bcat(ob[fd], ptr, len);
			return (0);
		}
		break;
	default:
		if (invcl[fd])
			vsb_cat(ob[fd], "\n");
		invcl[fd] = 0;
		break;
	}
	if (invcl[fd]) {
		vsb_cat(ob[fd], "\n");
		invcl[fd] = 0;
	}
	vsb_printf(ob[fd], "%5d %-12s %c %.*s\n",
	    fd, VSL_tags[tag],
	    ((spec & VSL_S_CLIENT) ? 'c' : (spec & VSL_S_BACKEND) ? 'b' : ' '),
	    len, ptr);
	switch (tag) {
	case SLT_ReqEnd:
	case SLT_BackendClose:
	case SLT_BackendReuse:
	case SLT_StatSess:
		vsb_finish(ob[fd]);
		if (vsb_len(ob[fd]) > 1)
			printf("%s\n", vsb_data(ob[fd]));
		vsb_clear(ob[fd]);
		break;
	default:
		break;
	}
	return (0);
}

static void
do_order(struct VSL_data *vd)
{
	int i;

	if (!bflag) {
		VSL_Select(vd, SLT_SessionOpen);
		VSL_Select(vd, SLT_SessionClose);
		VSL_Select(vd, SLT_ReqEnd);
	}
	if (!cflag) {
		VSL_Select(vd, SLT_BackendOpen);
		VSL_Select(vd, SLT_BackendClose);
		VSL_Select(vd, SLT_BackendReuse);
	}
	while (1) {
		i = VSL_Dispatch(vd, h_order, NULL);
		if (i == 0) {
			clean_order();
			fflush(stdout);
		}
		else if (i < 0)
			break;
	} 
	clean_order();
}

/*--------------------------------------------------------------------*/

static void
do_write(struct VSL_data *vd, const char *w_opt)
{
	FILE *wfile = NULL;
	unsigned u;
	int i;
	unsigned char *p;

	if (!strcmp(w_opt, "-"))
		wfile = stdout;
	else
		wfile = fopen(w_opt, "w");
	if (wfile == NULL) {
		perror(w_opt);
		exit (1);
	}
	u = 0;
	while (1) {
		i = VSL_NextLog(vd, &p);
		if (i < 0)
			break;
		if (i == 0) {
			fflush(wfile);
			fprintf(stderr, "\nFlushed\n");
		} else {
			i = fwrite(p, 5 + p[1], 1, wfile);
			if (i != 1)
				perror(w_opt);
			u++;
			if (!(u % 1000)) {
				fprintf(stderr, "%u\r", u);
				fflush(stderr);
			}
		}
	}
	exit (0);
}

/*--------------------------------------------------------------------*/

static void
usage(void)
{
	fprintf(stderr,
	    "usage: varnishlog [(stdopts)] [-oV] [-w file] [-r file]\n");
	exit(1);
}

int
main(int argc, char **argv)
{
	int i, c;
	int o_flag = 0;
	char *w_opt = NULL;
	struct VSL_data *vd;

	vd = VSL_New();
	
	while ((c = getopt(argc, argv, VSL_ARGS "oVw:")) != -1) {
		switch (c) {
		case 'o':
			o_flag = 1;
			break;
		case 'V':
			varnish_version("varnishlog");
			exit(0);
		case 'w':
			w_opt = optarg;
			break;
		case 'c':
			cflag = 1;
			if (VSL_Arg(vd, c, optarg) > 0)
				break;
			usage();
		case 'b':
			bflag = 1;
			if (VSL_Arg(vd, c, optarg) > 0)
				break;
			usage();
		default:
			if (VSL_Arg(vd, c, optarg) > 0)
				break;
			usage();
		}
	}

	if (o_flag && w_opt != NULL)
		usage();

	if (VSL_OpenLog(vd))
		exit (1);

	if (w_opt != NULL) 
		do_write(vd, w_opt);

	if (o_flag)
		do_order(vd);

	while (1) {
		i = VSL_Dispatch(vd, VSL_H_Print, stdout);
		if (i == 0)
			fflush(stdout);
		else if (i < 0)
			break;
	} 

	return (0);
}
