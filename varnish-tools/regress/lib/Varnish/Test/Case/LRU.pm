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

package Varnish::Test::Case::LRU;

use strict;
use base 'Varnish::Test::Case';

use Data::Dumper;

# Number of repetitions; total size of data set will be approximately
# (25 * $repeat * $repeat), and needs to be larger than the size of
# the storage file for the test to be meaningful.
our $repeat = 256;

sub _testLRU($$) {
    my ($self, $n) = @_;

    my $client = $self->new_client();
    my $uri = "/Varnish/Test/Case/LRU/$n";
    my $request = HTTP::Request->new('GET', $uri);
    $request->protocol('HTTP/1.1');
    $client->send_request($request, 2);
    my ($event, $response) =
	$self->run_loop('ev_client_response', 'ev_client_timeout');
    die "Timed out\n"
	if ($event eq 'ev_client_timeout');
    die "No (complete) response received\n"
	unless defined($response);
    die "Empty body\n"
	if $response->content() eq '';
    die "Incorrect body\n"
	if $response->content() !~ m/^(?:\Q$uri\E){$repeat}$/;
    $client->shutdown();
    return $response;
}

sub testLRU($) {
    my ($self) = @_;

    # Send $repeat requests in an attempt to eat through the entire
    # storage file.
    #
    # XXX We should check to see if the child dies while we do this.
    # XXX Currently, we will most likely get a client_timeout when
    # XXX testing a pre-LRU version of Varnish.
    for (my $n = 0; $n < $repeat; ++$n) {
	$self->_testLRU($n);
    }

    # Redo the first request; if we get a cached response (indicated
    # by a second XID in X-Varnish), the test is inconclusive and
    # needs to be re-run with either a smaller storage file or a
    # larger value for $repeat.
    my $response = $self->_testLRU(0);
    die "Inconclusive test\n"
	unless $response->header("X-Varnish") =~ m/^(\d+)$/;

    return 'OK';
}

sub ev_server_request($$$$) {
    my ($self, $server, $connection, $request) = @_;

    my $body = $request->uri() x $repeat;
    my $response = HTTP::Response->new(200, undef,
				       [ 'Content-Type', 'text/plain',
					 'Content-Length', length($body) ],
				       $body);
    $response->protocol('HTTP/1.1');
    $connection->send_response($response);
}

1;
