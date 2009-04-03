#!/usr/bin/perl -w
#-
# Copyright (c) 2007-2009 Linpro AS
# All rights reserved.
#
# Author: Dag-Erling Smørgrav <des@des.no>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
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

our %varnishstat;

our %ASPECTS = (
    'ratio' => {
	'title' => 'Hit / miss ratio',
	'type' => 'percent',
	'order' => [ 'hit', 'miss' ],
	'values' => {
	    'hit' => {
		'label' => 'hits',
		'numerator' => 'cache_hit',
		'denominator' => [ '+', 'cache_hit', 'cache_miss' ],
	    },
	    'miss' => {
		'label' => 'misses',
		'numerator' => 'cache_miss',
		'denominator' => [ '+', 'cache_hit', 'cache_miss' ],
	    },
	},
    },
    'usage' => {
	'title' => 'Cache file usage',
	'type' => 'percent',
	'order' => [ 'used', 'free' ],
	'values' => {
	    'used' => {
		'label' => 'used',
		'numerator' => 'sm_balloc',
		'denominator' => [ '+', 'sm_balloc', 'sm_bfree' ],
	    },
	    'free' => {
		'label' => 'free',
		'numerator' => 'sm_bfree',
		'denominator' => [ '+', 'sm_balloc', 'sm_bfree' ],
	    },
	},
    },
);

sub varnishstat($);
sub varnishstat($) {
    my $field = shift;

    if (ref($field) eq 'ARRAY') {
	die "Too few terms in $field"
	    if @$field < 2;
	my $acc = varnishstat($$field[1]);

	foreach (@$field[2..$#$field]) {
	    if ($$field[0] eq '+') {
		$acc += varnishstat($_);
	    } elsif ($$field[0] eq '-') {
		$acc -= varnishstat($_);
	    } elsif ($$field[0] eq '*') {
		$acc *= varnishstat($_);
	    } elsif ($$field[0] eq '/') {
		$acc /= varnishstat($_);
	    } else {
		die "Invalid spec for $field\n";
	    }
	}
	return $acc;
    }
    die "no such field: $field\n"
	unless defined($varnishstat{$field});
    return $varnishstat{$field};
}

sub value($$) {
    my $value = shift;
    my $type = shift;

    defined($value) || die "oops";
    if ($type eq 'count') {
	return varnishstat($value->{'field'});
    } elsif ($type eq 'gauge') {
	return varnishstat($value->{'field'});
    } elsif ($type eq 'percent') {
	return sprintf("%.1f", varnishstat($value->{'numerator'}) * 100.0 /
		       varnishstat($value->{'denominator'}));
    } elsif ($type eq 'ratio') {
	return sprintf("%.3f", varnishstat($value->{'numerator'}) /
		       varnishstat($value->{'denominator'}));
    } else {
	die "oops";
    }
}

sub order($) {
    my $aspect = shift;

    return (@{$aspect->{'order'}})
	if (defined($aspect->{'order'}));
    return (sort(keys(%{$aspect->{'values'}})));
}

sub measure($) {
    my $aspect = shift;

    defined($aspect) || die "oops";
    my @order = order($aspect);
    foreach (@order) {
	print "$_.value ",
	    value($aspect->{'values'}->{$_}, $aspect->{'type'}),
	    "\n";
    }
}

sub config($) {
    my $aspect = shift;

    defined($aspect) || die "oops";
    print "graph_category Varnish\n";
    print "graph_title $aspect->{'title'}\n";
    if ($aspect->{'type'} eq 'percent') {
	print "graph_scale no\n";
    }
    my @order = order($aspect);
    print "graph_order ", join(' ', @order), "\n";
    foreach (@order) {
	my $value = $aspect->{'values'}->{$_};
	print "$_.label $value->{'label'}\n";
	print "$_.graph yes\n";
	if ($aspect->{'type'} eq 'count') {
	    print "$_.type COUNTER\n";
	} elsif ($aspect->{'type'} eq 'gauge') {
	    print "$_.type GAUGE\n";
	} elsif ($aspect->{'type'} eq 'percent') {
	    print "$_.type GAUGE\n";
	    print "$_.min 0\n";
	    print "$_.max 100\n";
	    if ($_ eq $order[0]) {
		print "$_.draw AREA\n";
	    } else {
		print "$_.draw STACK\n";
	    }
	}
    }
}

sub read_varnishstat($) {
    my $name = shift;
    my ($rh, $wh);
    my $pid;

    pipe($rh, $wh)
	or die "pipe(): $!\n";
    defined($pid = fork())
	or die "fork(): $!\n";
    if ($pid == 0) {
	close($rh);
	open(STDOUT, ">&", $wh);
	exec "varnishstat", "-1", $name ? ("-n", $name) : ()
	    or die "exec(): $!\n";
	die "not reachable\n";
    }
    close($wh);
    while (<$rh>) {
	if (m/^(\w+)\s+(\d+)\s+(\d*\.\d*)\s+(\w.*)$/) {
	    $varnishstat{$1} = $2;
	    $ASPECTS{$1} = {
		'title' => $4,
		'type' => ($3 eq ".") ? 'gauge' : 'count',
		'values' => {
		    $1 => {
			'label' => $1,
			'field' => $1,
		    }
		}
	    };
	}
    }
    close($rh);
    waitpid($pid, 0)
	or die "waitpid(): $!\n";
    if ($? & 0x80) {
	die "varnishstat received signal ", $? && 0x7f, "\n";
    } elsif ($?) {
	die "varnishstat returned exit code ", $? >> 8, "\n";
    }
}

sub usage() {

    print STDERR "usage: varnish_<aspect> [config]\n";
    print STDERR "aspects: ", join(', ', sort keys %ASPECTS), "\n";
    exit 1;
}

MAIN:{
    read_varnishstat($ENV{'VARNISH_NAME'});

    my $aspect;
    ($aspect = $0) =~ s|^(?:.*/)varnish_(\w+)$|$1|;

    # XXX bug in munin-node
    shift @ARGV
	if (@ARGV && $ARGV[0] eq '');

    if (@ARGV == 0) {
	defined($ASPECTS{$aspect})
	    or usage();
	measure($ASPECTS{$aspect});
    } elsif (@ARGV == 1) {
	if ($ARGV[0] eq 'autoconf') {
	    print "yes\n";
	} elsif ($ARGV[0] eq 'aspects') {
	    foreach (sort keys %ASPECTS) {
		print "$_\n";
	    }
	} elsif ($ARGV[0] eq 'config') {
	    defined($ASPECTS{$aspect})
		or usage();
	    config($ASPECTS{$aspect});
	} else {
	    usage();
	}
    } else {
	usage();
    }
}
