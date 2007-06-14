#!/usr/bin/perl -w
#-
# Copyright (c) 2006 Linpro AS
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer
#    in this position and unchanged.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $Id$
#

use strict;

use FindBin;

use lib "$FindBin::Bin/lib";

use Getopt::Long;
use Varnish::Test;

sub usage() {
    print STDERR <<EOU;
USAGE:

  $0 CASE1 [ CASE2 ... ]

  where CASEn is either a full case name or a ticket number

Examples:

  $0 Ticket102
  $0 102

EOU
    exit 1;
}

MAIN:{
    GetOptions('help|h!' => \&usage)
	or usage();

    my $controller = new Varnish::Test;

    if (!@ARGV) {
	@ARGV = $controller->cases();
    } else {
	map { s/^(\d+)$/sprintf('Ticket%03d', $1)/e } @ARGV;
    }

    $controller->start_engine();
    foreach my $casename (@ARGV) {
	$controller->run_case($casename);
    }
    $controller->stop_engine();

    foreach my $case (@{$controller->{'cases'}}) {
	(my $name = ref($case)) =~ s/.*://;

	printf("%s: Successful: %d Failed: %d\n",
	       $name, $case->{'successful'}, $case->{'failed'});
    }
}
