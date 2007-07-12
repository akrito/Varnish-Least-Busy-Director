# $Id$

EXTRA_DIST = varnish_munin_plugin.pl

install-exec-local:
	${install_sh} -m 0755 -c varnish_munin_plugin.pl \
		${DESTDIR}${bindir}/varnish_
#	for aspect in `${DESTDIR}${bindir}/varnish_ aspects` ; do \
#		ln -fs varnish_ ${DESTDIR}${bindir}/varnish_$$aspect ; \
#	done
