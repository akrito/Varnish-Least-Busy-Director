#!/usr/bin/perl -w
#-
# Copyright (c) 2006-2007 Linpro AS
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

=head1 NAME

Varnish::Test::Case - test-case superclass

=head1 DESCRIPTION

Varnish::Test::Case is meant to be the superclass of specific
test-case clases. It provides functionality to run a number of tests
defined in methods whose names start with "test", as well as keeping
track of the number of successful or failed tests.

It also provides default event handlers for "ev_client_response" and
"ev_client_timeout", which are standard for most test-cases.

=cut

package Varnish::Test::Case;

use strict;

use Varnish::Test::Client;
use HTTP::Request;
use HTTP::Response;
use POSIX qw(strftime);
use Time::HiRes qw(gettimeofday tv_interval);

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

    $varnish->set_param('vcl_trace' => 'on');
    $self->run_loop('ev_varnish_command_ok');

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
    $self->{'start'} = [gettimeofday()];
    foreach my $method (@tests) {
	eval {
	    $self->{'count'} += 1;
	    $self->log(sprintf("%d: TRY: %s",
			       $self->{'count'}, $method));
	    my $result = $self->$method(@args);
	    $self->{'successful'} += 1;
	    $self->log(sprintf("%d: PASS: %s: %s\n",
			       $self->{'count'}, $method, $result || 'OK'));
	};
	if ($@) {
	    $self->{'failed'} += 1;
	    $self->log(sprintf("%d: FAIL: %s: %s",
			       $self->{'count'}, $method, $@));
	}
    }
    $self->{'stop'} = [gettimeofday()];
}

sub run_loop($@) {
    my ($self, @wait_for) = @_;

    return $self->{'engine'}->run_loop(@wait_for);
}

sub new_client($) {
    my ($self) = @_;

    return Varnish::Test::Client->new($self->{'engine'});
}

sub results($) {
    my ($self) = @_;

    no strict 'refs';
    my $name = ${ref($self)."::NAME"} || (split('::', ref($self)))[-1];
    my $descr = ${ref($self)."::DESCR"} || "N/A";
    return {
	'name' => $name,
	'descr' => $descr,
	'count' => $self->{'count'},
	'pass' => $self->{'successful'},
	'fail' => $self->{'failed'},
	'time' => tv_interval($self->{'start'}, $self->{'stop'}),
    };
}

#
# Default event handlers
#

sub ev_client_response($$$) {
    my ($self, $client, $response) = @_;

    return $response;
}

sub ev_client_timeout($$) {
    my ($self, $client) = @_;

    $client->shutdown();
    return $client;
}

sub ev_server_request($$$$) {
    my ($self, $server, $connection, $request) = @_;

    no strict 'refs';
    my $method = lc($request->method());
    my $handler;
    if ($self->can("server_$method")) {
	$handler = ref($self) . "::server_$method";
    } elsif ($self->can("server")) {
	$handler = ref($self) . "::server";
    } else {
	die "No server callback defined\n";
    }

    my $response = HTTP::Response->new();
    $response->code(200);
    $response->header('Date' =>
	strftime("%a, %d %b %Y %T GMT", gmtime(time())));
    $response->header('Server' => ref($self));
    $response->header('Connection' => 'keep-alive');
    $response->content('');
    $response->protocol('HTTP/1.1');
    $self->$handler($request, $response);
    $response->header('Content-Length' =>
		      length($response->content()));
    $connection->send_response($response);
}

sub ev_server_timeout($$) {
    my ($self, $srvconn) = @_;

    $srvconn->shutdown();
    return $srvconn;
}

#
# Client utilities
#

sub request($$$$;$$) {
    my ($self, $client, $method, $uri, $header, $content) = @_;

    my $req = HTTP::Request->new($method, $uri, $header);
    $req->protocol('HTTP/1.1');
    $req->header('Host' => 'varnish.example.com')
	unless $req->header('Host');
    $req->header('User-Agent' => ref($self))
	unless $req->header('User-Agent');
    if (defined($content)) {
	$req->header('Content-Type' => 'text/plain')
	    unless ($req->header('Content-Type'));
	$req->header('Content-Length' => length($content))
	    unless ($req->header('Content-Length'));
	$req->content($content);
    }
    $client->send_request($req, 4);
    my ($ev, $resp) =
	$self->run_loop('ev_server_timeout',
			'ev_client_timeout',
			'ev_client_response');
    die "Server timed out before receiving a complete request\n"
	if $ev eq 'ev_server_timeout';
    die "Client timed out before receiving a complete response\n"
	if $ev eq 'ev_client_timeout';
    die "Internal error\n"
	unless $resp && ref($resp) && $resp->isa('HTTP::Response');
    $resp->request($req);
    return $self->{'cached_response'} = $resp;
}

sub head($$$;$) {
    my ($self, $client, $uri, $header) = @_;

    return $self->request($client, 'HEAD', $uri, $header);
}

sub get($$$;$) {
    my ($self, $client, $uri, $header) = @_;

    return $self->request($client, 'GET', $uri, $header);
}

sub post($$$;$$) {
    my ($self, $client, $uri, $header, $body) = @_;

    $header = []
	unless defined($header);
    return $self->request($client, 'POST', $uri, $header, $body);
}

sub assert_code($$;$) {
    my ($self, $code, $resp) = @_;

    $resp = $self->{'cached_response'}
        unless defined($resp);
    die "Expected $code, got @{[$resp->code]}\n"
	unless $resp->code == $code;
}

sub assert_ok($;$) {
    my ($self, $resp) = @_;

    $resp = $self->{'cached_response'}
        unless defined($resp);

    $self->assert_code(200, $resp);
}

sub assert_xid($;$) {
    my ($self, $resp) = @_;

    $resp = $self->{'cached_response'}
        unless defined($resp);

    die "No X-Varnish header\n"
	unless (defined($resp->header('X-Varnish')));
    die "Invalid X-Varnish header\n"
	unless ($resp->header('X-Varnish') =~ m/^\d+(?: \d+)?$/);
}

sub assert_no_xid($;$) {
    my ($self, $resp) = @_;

    $resp = $self->{'cached_response'}
        unless defined($resp);

    die "X-Varnish header present where none expected\n"
	if (defined($resp->header('X-Varnish')));
}

sub assert_cached($;$) {
    my ($self, $resp) = @_;

    $resp = $self->{'cached_response'}
        unless defined($resp);

    my $uri = $resp->request->uri;
    die "$uri should be cached but isn't\n"
	unless $resp->header('X-Varnish') =~ /^\d+ \d+$/;
}

sub assert_uncached($;$) {
    my ($self, $resp) = @_;

    $resp = $self->{'cached_response'}
        unless defined($resp);

    my $uri = $resp->request->uri;
    die "$uri shouldn't be cached but is\n"
	if $resp->header('X-Varnish') =~ /^\d+ \d+$/;
}

sub assert_header($$;$$) {
    my ($self, $header, $re, $resp) = @_;

    $resp = $self->{'cached_response'}
        unless defined($resp);

    die "$header: header missing\n"
	unless defined($resp->header($header));
    if (defined($re)) {
	die "$header: header does not match\n"
	    unless $resp->header($header) =~ m/$re/;
    }
}

sub assert_body($;$$) {
    my ($self, $re, $resp) = @_;

    $resp = $self->{'cached_response'}
        unless defined($resp);

    die "Response has no body\n"
	unless defined($resp->content());
    if (defined($re)) {
	die "Response body does not match\n"
	    unless $resp->content() =~ m/$re/;
    }
}

sub assert_no_body($;$) {
    my ($self, $resp) = @_;

    $resp = $self->{'cached_response'}
        unless defined($resp);
    die "Response shouldn't have a body, but does\n"
	if defined($resp->content()) && length($resp->content());
}

#
# Miscellaneous
#

sub usleep($$) {
    my ($self, $usec) = @_;

    select(undef, undef, undef, $usec / 1000000.0);
}

1;
