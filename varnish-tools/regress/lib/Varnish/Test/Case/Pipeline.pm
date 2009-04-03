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

package Varnish::Test::Case::Pipeline;

use strict;
use base 'Varnish::Test::Case';

our $DESCR = "Tests Varnish's ability to handle pipelined requests.";
our $NOTES = "1.1.2 is expected to fail one of two subtests.";

our %CONTENT = (
    'Gibson' => "The sky above the port was the color of television, tuned to a dead channel.",
    'Tolkien' => "In a hole in the ground there lived a hobbit.",
    'Williams' => "I have always depended upon the kindness of strangers.",
);

our $REPS = 4096;

our $VCL = <<EOVCL;
sub vcl_recv {
    if (req.request == "POST") {
	pass;
    }
}
EOVCL

sub testPipelineGet($) {
    my ($self) = @_;

    my $client = $self->new_client;
    foreach my $author (sort keys %CONTENT) {
	$self->get($client, "/$author");
    }
    foreach my $author (sort keys %CONTENT) {
	$self->wait();
	$self->assert_ok();
	$self->assert_xid();
	$self->assert_body(qr/\Q$CONTENT{$author}\E/);
    }

    return 'OK'
}

sub testPipelinePost($) {
    my ($self) = @_;

    my $client = $self->new_client;
    foreach my $author (sort keys %CONTENT) {
	$self->post($client, "/$author", [], $CONTENT{$author} x $REPS);
    }
    foreach my $author (sort keys %CONTENT) {
	$self->wait();
	$self->assert_ok();
	$self->assert_xid();
	$self->assert_body(qr/\Q$CONTENT{$author}\E/);
    }

    return 'OK'
}

sub server($$$) {
    my ($self, $request, $response) = @_;

    my ($author) = ($request->uri =~ m/(\w+)$/);
    if ($CONTENT{$author}) {
	if ($request->method eq 'POST') {
	    die "Not the content I expected\n"
		unless $request->content eq $CONTENT{$author} x $REPS;
	}
	$response->content($CONTENT{$author});
    } else {
	$response->code(404);
	$response->content("Unknown author.\n");
    }
}

1;
