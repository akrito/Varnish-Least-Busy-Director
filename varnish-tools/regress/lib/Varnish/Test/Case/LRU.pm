#!/usr/bin/perl -w
#-
# Copyright (c) 2007-2008 Linpro AS
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

our $prefix = __PACKAGE__;

# Number of repetitions; total size of data set will be approximately
# (25 * $repeat * $repeat), and needs to be larger than the size of
# the storage file for the test to be meaningful.
our $repeat = 256;

our $DESCR = "Tests the LRU code by running more data through Varnish" .
    " than the cache can hold, while simultaneously repeatedly requesting" .
    " one particular object, which should remain in cache throughout.  The" .
    " total amount of space consumed is approximately $repeat * round(" .
    ((length(__PACKAGE__) + 5) * $repeat) . ", PAGE_SIZE).";

sub _testLRU($$) {
    my ($self, $n) = @_;

    my $client = $self->new_client();
    my $uri = __PACKAGE__ . "::$n";
    my $request = $self->get($client, $uri);
    my $response = $self->wait();
    $self->assert_body(qr/^(?:\Q$uri\E){$repeat}$/);
    $client->shutdown();
    return $response;
}

sub testLRU($) {
    my ($self) = @_;

    my $response = $self->_testLRU(0);
    die "Invalid X-Varnish in response"
	unless $response->header("X-Varnish") =~ m/^(\d+)$/;
    my $xid0 = $1;

    # Send $repeat requests in an attempt to eat through the entire
    # storage file.  Keep one object hot throughout.
    #
    #XXX We should check to see if the child dies while we do this.
    #XXX Currently, when testing a pre-LRU version of Varnish, we will
    #XXX most likely get a client timeout and the test framework will
    #XXX get stuck.
    for (my $n = 1; $n < $repeat; ++$n) {
	# cold object
	$self->_testLRU($n);

	# Slow down!  If we run through the cache faster than the
	# hysteresis in the LRU code, the hot object will be evicted.
	$self->usleep(100000);

	# hot object
	$response = $self->_testLRU(0);
	die "Cache miss on hot object"
	    unless $response->header("X-Varnish") =~ m/^(\d+)\s+($xid0)$/o;
    }

    # Re-request an object which should have been evicted.  If we get
    # a cache hit, the test is inconclusive and needs to be re-run
    # with a smaller storage file or a larger value of $repeat.
    $response = $self->_testLRU(1);
    die "Inconclusive test\n"
	unless $response->header("X-Varnish") =~ m/^(\d+)$/;

    return 'OK';
}

sub server($$$) {
    my ($self, $request, $response) = @_;

    $response->content($request->uri() x $repeat);
    $response->header('Cache-Control' => 'max-age=3600');
}

1;
