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

use Data::Dumper;

our $VCL = <<EOVCL;
sub vcl_recv {
	if (req.request == "REPURGE") {
		purge(req.url);
		error 404 "Purged";
	}
}
EOVCL

our $KEEP_URL = '/will-be-kept';
our $PURGE_URL = '/will-be-purged';
our $PURGE_RE = 'purge';

sub get($$$) {
    my ($self, $client, $url) = @_;

    my $req = HTTP::Request->new('GET', $url);
    $req->protocol('HTTP/1.1');
    $client->send_request($req, 2);
    my ($ev, $resp) =
	$self->run_loop('ev_client_response', 'ev_client_timeout');
    die "Client time-out before receiving a (complete) response\n"
	if $ev eq 'ev_client_timeout';
    die "Request failed\n"
	unless $resp->code == 200;
    return $resp;
}

sub get_cached($$$) {
    my ($self, $client, $url) = @_;

    my $resp = $self->get($client, $url);
    die "$url should be cached but isn't\n"
	unless $resp->header('x-varnish') =~ /^\d+ \d+$/;
}

sub get_uncached($$$) {
    my ($self, $client, $url) = @_;

    my $resp = $self->get($client, $url);
    die "$url shouldn't be cached but is\n"
	if $resp->header('x-varnish') =~ /^\d+ \d+$/;
}

sub purge($$$) {
    my ($self, $client, $re) = @_;

    my $req = HTTP::Request->new('REPURGE', $re);
    $req->protocol('HTTP/1.1');
    $client->send_request($req, 2);
    my ($ev, $resp) =
	$self->run_loop('ev_client_response', 'ev_client_timeout');
    die "Client time-out before receiving a (complete) response\n"
	if $ev eq 'ev_client_timeout';
}

sub testPagePurged($) {
    my ($self) = @_;

    my $client = $self->new_client;
    my $resp;

    # Warm up the cache
    $self->get($client, $KEEP_URL);
    $self->get($client, $PURGE_URL);

    # Verify the state of the cache
    $self->get_cached($client, $KEEP_URL);
    $self->get_cached($client, $PURGE_URL);

    # Send the purge request
    $self->purge($client, $PURGE_RE);

    # Verify the state of the cache
    $self->get_cached($client, $KEEP_URL);
    $self->get_uncached($client, $PURGE_URL);

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
