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

package Varnish::Test::Case::Vary;

use strict;
use base 'Varnish::Test::Case';

our %languages = (
    'en' => "Hello World!\n",
    'no' => "Hallo Verden!\n",
);

sub testVary($) {
    my ($self) = @_;

    my $client = $self->new_client;
    my $request = HTTP::Request->new('GET', '/');

    foreach my $lang (keys %languages) {
	$request->header('Accept-Language', $lang);
	$request->protocol('HTTP/1.1');
	$client->send_request($request, 2);
	my ($event, $response) =
	    $self->run_loop('ev_client_response', 'ev_client_timeout');
	die "No (complete) response received\n"
	    unless defined($response);
	die "Empty body\n"
	    if $response->content() eq '';
	die "Incorrect body\n"
	    if $response->content() ne $languages{$lang};
    }
}

sub ev_server_request($$$$) {
    my ($self, $server, $connection, $request) = @_;

    my $body;
    my @headers;
    if (my $lang = $request->header("Accept-Language")) {
	$lang = 'en'
	    unless ($lang && $languages{$lang});
	$body = $languages{$lang};
	push(@headers, ('Language', $lang));
    } else {
	die 'Not ready for this!';
    }

    my $response = HTTP::Response->new(200, undef,
				       [ 'Content-Length', length($body),
					 'Vary', 'Accept-Language',
					 @headers ],
				       $body);
    $response->protocol('HTTP/1.1');
    $connection->send_response($response);
}

1;
