#!/usr/bin/perl -w
#-
# Copyright (c) 2007 Linpro AS
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

package Varnish::Fetcher;

use strict;
use Getopt::Long;
use IO::Handle;
use IO::Multiplex;
use LWP::UserAgent;
use Socket;
use URI;

our %TODO;
our %DONE;
our %CHILD;
our $BUSY;

sub new($$) {
    my ($this, $mux, $fh) = @_;
    my $class = ref($this) || $this;

    bless {
	'mux' => $mux,
	'fh' => $fh,
	'url' => undef,
    };
}

sub run($$) {
    my ($self, $s) = @_;

    my $ua = new LWP::UserAgent();
    for (;;) {
	$0 = "[fetcher] idle";
	my $url = <$s>;
	exit(0)
	    unless defined($url);
	chomp($url);
	die "no more work\n"
	    if $url eq "done";
	$0 = "[fetcher] requesting $url";
	print STDERR "Retrieving $url\n";
	my $resp = $ua->get($url);
	$0 = "[fetcher] checking $url";
	if ($resp->header('Content-Type') =~ m/^text\//) {
	    my %urls = map { $_ => 1 }
	    ($resp->content =~ m/\b(?:href|src)=[\'\"](.+?)[\'\"]/g);
	    foreach (keys(%urls)) {
		$s->write("add $_\n");
	    }
	}
	$0 = "[fetcher] ready";
	$s->write("ready\n");
    }
}

sub send_url($) {
    my ($child) = @_;

    die "child busy\n"
	if $child->{'url'};
    return undef
	unless (keys(%TODO));
    my $url = (keys(%TODO))[0];
    delete $TODO{$url};
    $DONE{$url} = 1;
    $child->{'url'} = $url;
    $child->{'mux'}->write($child->{'fh'}, "$url\n");
    ++$BUSY;
}

sub get_url($$) {
    my ($child, $url) = @_;

    die "child not busy\n"
	unless $child->{'url'};
    my $uri = URI->new_abs($1, $child->{'url'});
    $url = $uri->canonical;
    if ($uri->scheme() ne 'http' ||
	$uri->host_port() ne URI->new($child->{'url'})->host_port()) {
	print STDERR "Rejected $url\n";
	return;
    }
    return if $TODO{$url} || $DONE{$url};
    $TODO{$url} = 1;
}

sub mux_input($$$$) {
    my ($child, $mux, $fh, $input) = @_;

    die "unknown child\n"
	unless $child;

    while ($$input =~ s/^(.*?)\n//) {
	my $line = $1;
	if ($line eq "ready") {
	    $$child{'url'} = '';
	    --$BUSY;
	    $mux->endloop();
	} elsif ($line =~ m/^add (.*?)$/) {
	    get_url($child, $1);
	} else {
	    die "can't grok [$line]\n";
	}
    }
}

sub fetcher($@) {
    my ($n, @urls) = @_;

    my $mux = new IO::Multiplex;

    # prepare work queue
    foreach my $url (@urls) {
	$TODO{URI->new($url)->canonical} = 1;
    }

    # start children
    $BUSY = 0;
    for (my $i = 0; $i < $n; ++$i) {
	my ($s1, $s2);
	socketpair($s1, $s2, AF_UNIX, SOCK_STREAM, PF_UNSPEC);
	$s1->autoflush(1);
	$s2->autoflush(1);
	my $child = __PACKAGE__->new($mux, $s1);
	my $pid = fork();
	last unless defined($pid);
	if ($pid == 0) {
	    close($s1);
	    $child->run($s2);
	    die "not reachable";
	} else {
	    close($s2);
	    $CHILD{$i} = $child;
	    $mux->add($s1);
	    $mux->set_callback_object($child, $s1);
	}
    }

    # main loop
    for (;;) {
	foreach my $child (values(%CHILD)) {
	    $child->send_url()
		unless $child->{'url'};
	}
	last unless $BUSY;
	$mux->loop();
    }

    # done
    foreach my $child (values(%CHILD)) {
	$mux->close($$child{'fh'});
    }
}

sub usage() {

    print STDERR "usage: $0 [-j n] URL ...\n";
    exit(1);
}

MAIN:{
    my $jobs = 1;
    GetOptions("j|jobs=i" => \$jobs)
	or usage();
    $jobs > 0
	or usage();
    @ARGV
	or usage();
    fetcher($jobs, @ARGV);
}
