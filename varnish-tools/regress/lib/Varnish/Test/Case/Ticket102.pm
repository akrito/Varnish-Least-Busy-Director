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

package Varnish::Test::Case::Ticket102;

use strict;
use base 'Varnish::Test::Case';

our $DESCR = "Checks that Varnish includes the response body when" .
    " handling GET and POST, but not when handling HEAD.";

our $VCL = <<EOVCL;
sub vcl_recv {
	if (req.request == "POST" &&
	    (!req.http.content-length || req.http.content-length == "0")) {
		lookup;
	}
}
EOVCL

our $BODY = "Hello World!\n";

sub testBodyInCachedPOST($) {
    my ($self) = @_;

    my $client = $self->new_client;

    $self->get($client, '/');
    $self->assert_body($BODY);
    $self->assert_uncached();

    $self->post($client, '/');
    $self->assert_body($BODY);
    $self->assert_cached();

    $self->head($client, '/');
    $self->assert_no_body();
    $self->assert_cached();

    $client->shutdown();

    return 'OK';
}

sub server($$$) {
    my ($self, $request, $response) = @_;

    $response->content($BODY);
}

1;
