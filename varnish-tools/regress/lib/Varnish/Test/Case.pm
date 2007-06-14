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

sub init($) {
    my ($self) = @_;

    $self->{'engine'}->{'case'} = $self;

    my $varnish = $self->{'engine'}->{'varnish'};

    # Load VCL script if we have one
    no strict 'refs';
    if (${ref($self)."::VCL"}) {
	my $vcl = $varnish->backend_block('main') . ${ref($self)."::VCL"};

	$varnish->send_vcl(ref($self), $vcl);
	$self->run_loop('ev_varnish_command_ok');
	$varnish->use_vcl(ref($self));
	$self->run_loop('ev_varnish_command_ok');
    }

    # Start the child
    $varnish->start_child();
    $self->run_loop('ev_varnish_child_started');
}

sub fini($) {
    my ($self) = @_;

    my $varnish = $self->{'engine'}->{'varnish'};

    # Stop the worker process
    $varnish->stop_child();
    # Wait for both events, the order is unpredictable, so wait for
    # any of them both times.
    $self->run_loop('ev_varnish_child_stopped', 'ev_varnish_command_ok');
    $self->run_loop('ev_varnish_child_stopped', 'ev_varnish_command_ok');

    # Revert to initial VCL script
    no strict 'refs';
    if (${ref($self)."::VCL"}) {
	$varnish->use_vcl('boot');
	$self->run_loop('ev_varnish_command_ok', 'ev_varnish_command_unknown');
    }

    delete $self->{'engine'}->{'case'};

    if ($self->{'failed'}) {
	die sprintf("%d out of %d tests failed\n",
		    $self->{'failed'}, $self->{'count'});
    }
}

sub run($;@) {
    my ($self, @args) = @_;

    $self->log('Starting ' . ref($self));

    no strict 'refs';
    my @tests = @{ref($self)."::TESTS"};
    if (!@tests) {
	@tests = sort grep {/^test(\w+)/} (keys %{ref($self) . '::'});
    }
    foreach my $method (@tests) {
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
}

sub run_loop($@) {
    my ($self, @wait_for) = @_;

    return $self->{'engine'}->run_loop(@wait_for);
}

sub new_client($) {
    my ($self) = @_;

    return Varnish::Test::Client->new($self->{'engine'});
}

sub ev_client_response($$$) {
    my ($self, $client, $response) = @_;

    return $response;
}

sub ev_client_timeout($$) {
    my ($self, $client) = @_;

    $client->shutdown(2);
    return $client;
}

1;
