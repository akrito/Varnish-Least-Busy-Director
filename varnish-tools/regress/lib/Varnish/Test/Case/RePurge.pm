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

package Varnish::Test::Case::RePurge;

use strict;
use base 'Varnish::Test::Case';

our $DESCR = "Tests the VCL purge() function by warming up the cache," .
    " then submitting a request that causes part of it to be purged," .
    " before finally verifying that the objects that should have been" .
    " purged were and those that shouldn't weren't.";

our $VCL = <<EOVCL;
sub vcl_recv {
    if (req.request == "REPURGE") {
	purge_url(req.url);
	error 404 "Purged";
    }
}
EOVCL

our $KEEP_URL = '/will-be-kept';
our $PURGE_URL = '/will-be-purged';
our $PURGE_RE = 'purge';

sub testPagePurged($) {
    my ($self) = @_;

    my $client = $self->new_client;

    # Warm up the cache
    $self->get($client, $KEEP_URL);
    $self->assert_ok();
    $self->get($client, $PURGE_URL);
    $self->assert_ok();

    # Verify the state of the cache
    $self->get($client, $KEEP_URL);
    $self->assert_ok();
    $self->assert_cached();
    $self->get($client, $PURGE_URL);
    $self->assert_ok();
    $self->assert_cached();

    # Send the purge request
    $self->request($client, 'REPURGE', $PURGE_RE);

    # Verify the state of the cache
    $self->get($client, $KEEP_URL);
    $self->assert_ok();
    $self->assert_cached();
    $self->get($client, $PURGE_URL);
    $self->assert_ok();
    $self->assert_uncached();

    $client->shutdown();

    return 'OK';
}

sub ev_server_request($$$$) {
    my ($self, $server, $connection, $request) = @_;

    my $body = $request->url;
    my $response = HTTP::Response->new(200, undef,
				       [ 'Content-Length', length($body),
					 'Connection', 'Keep-Alive' ],
				       $body);
    $response->protocol('HTTP/1.1');
    $connection->send_response($response);
}

1;
