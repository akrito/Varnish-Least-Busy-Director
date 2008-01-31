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

package Varnish::Test::Case::Ticket164;

use strict;
use base 'Varnish::Test::Case';

our $DESCR = "Exercises a bug in the backend HTTP path.";

sub testGarbledResponse($) {
    my ($self) = @_;

    my $client = $self->new_client;

    $self->get($client, '/garbled');
    $self->wait();
    $self->assert_code(503);
    $client->shutdown();

    return 'OK';
}

sub testPartialResponse($) {
    my ($self) = @_;

    my $client = $self->new_client;

    $self->get($client, '/partial');
    $self->wait();
    $self->assert_code(503);
    $client->shutdown();

    return 'OK';
}

sub testNoResponse($) {
    my ($self) = @_;

    my $client = $self->new_client;

    $self->get($client, '/none');
    $self->wait();
    $self->assert_code(503);
    $client->shutdown();

    return 'OK';
}

sub ev_server_request($$$$) {
    my ($self, $server, $connection, $request) = @_;

    if ($request->uri =~ m/garbled/) {
	$connection->write("Garbled response\r\n");
    } elsif ($request->uri =~ m/partial/) {
	$connection->write("HTTP/1.1 200 OK\r\n");
	$connection->write("Oops: incomplete response\r\n");
    }
    $connection->shutdown();
}

1;
