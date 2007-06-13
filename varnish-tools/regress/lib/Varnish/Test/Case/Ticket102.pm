#!/usr/bin/perl -Tw
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

package Varnish::Test::Case::Ticket102;

use strict;
use base 'Varnish::Test::Case';

use Carp 'croak';

our $VCL = <<EOVCL;
sub vcl_recv {
	if (req.request == "POST" &&
	    (!req.http.content-length || req.http.content-length == "0")) {
		lookup;
	}
}
EOVCL

our $body = "Hello World!\n";

sub testBodyInCachedPOST($) {
    my ($self) = @_;

    my $client = $self->new_client;
    for (my $i = 0; $i < 2; $i++) {
	my $request = HTTP::Request->new('POST', '/');
	$request->protocol('HTTP/1.1');
	$client->send_request($request, 2);
	my $response = $self->run_loop;
	croak 'No (complete) response received' unless defined($response);
	croak 'Empty body' if $response->content eq '';
	croak 'Incorrect body' if $response->content ne $body;
    }
}

sub ev_server_request($$$$) {
    my ($self, $server, $connection, $request) = @_;

    my $response = HTTP::Response->new(200, undef,
				       [ 'Content-Length', length($body),
					 'Connection', 'Keep-Alive' ],
				       $body);
    $response->protocol('HTTP/1.1');
    $connection->send_response($response);
}

1;
