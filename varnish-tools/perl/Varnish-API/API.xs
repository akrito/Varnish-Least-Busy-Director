#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <varnish/varnishapi.h>

#include "const-c.inc"

int
dispatch_callback(void *priv, enum shmlogtag tag, unsigned fd, unsigned len,
    unsigned spec, const char *ptr) {
    dSP;
    int count;
    int rv;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSVpv(VSL_tags[tag],0)));
    XPUSHs(sv_2mortal(newSViv(fd)));
    XPUSHs(sv_2mortal(newSViv(spec)));
    XPUSHs(sv_2mortal(newSVpv(ptr,0)));
    PUTBACK;
    count = call_sv((SV*) priv, G_SCALAR);
    SPAGAIN;
    rv = POPi;
    PUTBACK;    
    FREETMPS;
    LEAVE;
    return (rv);
}

MODULE = Varnish::API		PACKAGE = Varnish::API		


INCLUDE: const-xs.inc

char*
VSL_tags(tag)
	int tag
	CODE:
	RETVAL = (char*) VSL_tags[tag];
	OUTPUT:
	RETVAL

int
VSL_Dispatch(vd, func)
	SV* vd;
	SV* func
	PPCODE:
	struct VSL_data* data = (struct VSL_data*) SvIV(vd);
	VSL_Dispatch(data, dispatch_callback, func);
	

const char *
VSL_Name()

SV*
VSL_New()
	PPCODE:
	struct VSL_data* vd = VSL_New();
	ST(0) = newSViv((IV)vd);
	sv_2mortal(ST(0));
	XSRETURN(1);

SV* 
VSL_NextLog(vd)
	SV* vd;
	PPCODE:
	struct VSL_data* data = (struct VSL_data*) SvIV(vd);
	unsigned char *p;
	VSL_NextLog(data, &p);
	ST(0) = newSVpv(p,SHMLOG_NEXTTAG + SHMLOG_LEN(p));
	sv_2mortal(ST(0));
	XSRETURN(1);
	
void
VSL_NonBlocking(vd, nb)
	struct VSL_data *	vd
	int	nb

int
VSL_OpenLog(vd, varnish_name)
	SV*	vd
	const char *	varnish_name
	CODE:
	struct VSL_data* data = (struct VSL_data*) SvIV(vd);
	VSL_OpenLog(data, varnish_name);
	

struct varnish_stats *
VSL_OpenStats(varnish_name)
	const char *	varnish_name

void
VSL_Select(vd, tag)
	struct VSL_data *	vd
	unsigned	tag


int
varnish_instance(n_arg, name, namelen, dir, dirlen)
	const char *	n_arg
	char *	name
	size_t	namelen
	char *	dir
	size_t	dirlen
