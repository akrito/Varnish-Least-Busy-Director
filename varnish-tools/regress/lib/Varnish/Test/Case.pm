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

package Varnish::Test::Case;

use strict;
use Carp 'croak';

use Varnish::Test::Logger;

use HTTP::Request;
use HTTP::Response;

sub new($$) {
    my ($this, $engine) =  @_;
    my $class = ref($this) || $this;

    my $self = bless({ 'engine' => $engine,
		       'count' => 0,
		       'successful' => 0,
		       'failed' => 0 }, $class);
}

sub log($$) {
    my ($self, $str) = @_;

    $self->{'engine'}->log($self, 'CAS: ', $str);
}

sub run($;@) {
    my ($self, @args) = @_;

    $self->{'engine'}->{'case'} = $self;

    $self->log('Starting ' . ref($self));

    no strict 'refs';
    foreach my $method (keys %{ref($self) . '::'}) {
	next unless $method =~ m/^test([A-Z]\w+)/;
	eval {
	    $self->{'count'} += 1;
	    my $result = $self->$method(@args);
	    $self->{'successful'} += 1;
	    $self->log(sprintf("%d: PASS: %s: %s\n",
			       $self->{'count'}, $method, $result || ''));
	};
	if ($@) {
	    $self->{'failed'} += 1;
	    $self->log(sprintf("%d: FAIL: %s: %s",
			       $self->{'count'}, $method, $@));
	}
    }

    delete $self->{'engine'}->{'case'};
}

sub run_loop($) {
    my ($self) = @_;

    $self->{'engine'}->run_loop;
}

sub pause_loop($;@) {
    my ($self, @args) = @_;

    $self->{'engine'}->pause_loop(@args);
}

sub new_client($) {
    my ($self) = @_;

    return Varnish::Test::Client->new($self->{'engine'});
}

sub ev_client_response($$$) {
    my ($self, $client, $response) = @_;

    $self->{'engine'}->pause_loop($response);
}

sub ev_client_timeout($$) {
    my ($self, $client) = @_;

    $client->shutdown(2);
    $self->{'engine'}->pause_loop;
}

1;
