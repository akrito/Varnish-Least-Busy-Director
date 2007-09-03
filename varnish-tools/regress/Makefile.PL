# $Id$

use ExtUtils::MakeMaker;

WriteMakefile(NAME => 'Varnish::Test',
	      EXE_FILES => ['bin/varnish-regress.pl']);
