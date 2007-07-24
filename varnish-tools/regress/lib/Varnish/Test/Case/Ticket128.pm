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

package Varnish::Test::Case::Ticket128;

use strict;
use base 'Varnish::Test::Case';

our $CODE = 400;
our $MESSAGE = "These are not the droids you are looking for";

our $VCL = <<EOVCL;
sub vcl_recv {
    error $CODE "$MESSAGE";
}
EOVCL

sub testSyntheticError($) {
    my ($self) = @_;

    my $client = $self->new_client;
    my $request = HTTP::Request->new('GET', '/');
    $request->protocol('HTTP/1.0');
    $client->send_request($request, 2);

    my ($event, $response) = $self->run_loop('ev_client_response', 'ev_client_timeout');

    die "Client time-out before receiving a (complete) response\n"
	if $event eq 'ev_client_timeout';
    die "Incorrect response code\n"
	if $response->code != $CODE;
    die "Incorrect response message\n"
	unless $response->content =~ m/\Q$MESSAGE\E/o;

    $client->shutdown();

    return 'OK';
}

1;
