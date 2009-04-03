#!/usr/bin/perl -w
#-
# Copyright (c) 2006-2009 Linpro AS
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

=head1 NAME

varnish-regress.pl - run Varnish regression tests

=head1 DESCRIPTION

This program is a thin wrapper around the L<Varnish::Test> regression
test framework library. Using this library, regression tests are
performed on Varnish.

The Varnish daemon (L<varnishd>) must be available in one of the
directories given by the "PATH" environment variable.

By default, this program will run all test-cases available in the
regression test framework library, or the test-cases selected by name
as arguments on the command line.

=head1 OUTPUT

STDERR is used to continually report progress during testing.

STDOUT is used to output a HTML-formatted report at the end of the
run, provided that execution does not abort prematurely for any
reason.

=cut

use strict;

eval { require Varnish::Test };
if ($@) {
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;
use Varnish::Test;
use Varnish::Test::Report::HTML;

sub usage() {
    print STDERR <<EOU;
USAGE:

  $0 [CASE ...]

  where CASE is either a full case name or a ticket number.  By
  default, all available test cases will be run.

Examples:

  $0
  $0 Ticket102
  $0 102

EOU
    exit 1;
}

MAIN:{
    GetOptions('help|h!' => \&usage)
	or usage();

    my $controller = new Varnish::Test;
    my @all_cases = $controller->cases();

    if (@ARGV == 1 && $ARGV[0] eq 'list') {
	print join(' ', @all_cases), "\n";
	exit 0;
    }

    if (!@ARGV) {
	@ARGV = @all_cases;
    } else {
	map { s/^(\d+)$/sprintf('Ticket%03d', $1)/e } @ARGV;
    }

    $controller->start_engine();
    foreach my $casename (@ARGV) {
	$controller->run_case($casename);
    }
    $controller->stop_engine();

    my $report = new Varnish::Test::Report::HTML;
    $report->run($controller->results());
}

=head1 SEE ALSO

L<Varnish::Test>
L<Varnish::Test::Report>

=cut
