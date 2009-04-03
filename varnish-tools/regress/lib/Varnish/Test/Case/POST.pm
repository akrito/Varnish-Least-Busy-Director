#!/usr/bin/perl -w
#-
# Copyright (c) 2007-2009 Linpro AS
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

package Varnish::Test::Case::POST;

use strict;
use base 'Varnish::Test::Case';

our $DESCR = "Tests Varnish's ability to correctly pass POST requests" .
    " to the backend, and their replies back to the client.";
our $NOTES = "1.1.2 is expected to fail one of three subtests.";

our $VCL = <<EOVCL;
sub vcl_recv {
    if (req.request == "POST") {
	if (!req.http.content-length || req.http.content-length == "0") {
	    lookup;
	}
	if (req.url ~ "pass") {
	    pass;
	}
	pipe;
    }
}
EOVCL

our $MAGIC_WORDS = "Squeamish Ossifrage";
our $NOTHING_HAPPENS = "Nothing happens.";

sub testPassPOST($) {
    my ($self) = @_;

    my $client = $self->new_client;
    $self->post($client, "/pass_me", [], $MAGIC_WORDS);
    $self->wait();
    $self->assert_ok();
    $self->assert_xid();
    $self->assert_body(qr/\Q$MAGIC_WORDS\E/);

    return 'OK';
}

sub testPipePOST($) {
    my ($self) = @_;

    my $client = $self->new_client;
    $self->post($client, "/pipe_me", [], $MAGIC_WORDS);
    $self->wait();
    $self->assert_ok();
    $self->assert_no_xid();
    $self->assert_body(qr/\Q$MAGIC_WORDS\E/);

    return 'OK';
}

sub testCachePOST($) {
    my ($self) = @_;

    my $client = $self->new_client;

    # Warm up the cache
    $self->post($client, "/cache_me");
    $self->wait();
    $self->assert_ok();
    $self->assert_uncached();
    $self->assert_body(qr/\Q$NOTHING_HAPPENS\E/);

    # Verify that the request was cached
    $self->post($client, "/cache_me");
    $self->wait();
    $self->assert_ok();
    $self->assert_cached();
    $self->assert_body(qr/\Q$NOTHING_HAPPENS\E/);

    return 'OK';
}

sub server_get($$$) {
    my ($self, $request, $response) = @_;

    # Varnish will always use GET when fetching a presumably cacheable
    # object from the backend.  This is not a bug.
    goto &server_post
	if ($request->uri =~ m/cache_me/);
    die "Got GET request instead of POST\n";
}

sub server_post($$$) {
    my ($self, $request, $response) = @_;

    if ($request->content()) {
	$response->content("The Magic Words are " . $request->content());
    } else {
	$response->content($NOTHING_HAPPENS);
    }
}

1;
