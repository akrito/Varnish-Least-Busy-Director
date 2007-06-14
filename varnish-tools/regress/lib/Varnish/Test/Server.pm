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

package Varnish::Test::Server;

use strict;

use IO::Socket::INET;

sub new($$) {
    my ($this, $engine, $attrs) = @_;
    my $class = ref($this) || $this;

    my ($host, $port) = split(':', $engine->{'config'}->{'server_address'});

    my $socket = IO::Socket::INET->new('Proto'     => 'tcp',
				       'LocalAddr' => $host,
				       'LocalPort' => $port,
				       'Listen'    => 4,
				       'ReuseAddr' => 1)
      or die "socket(): $!\n";

    my $self = bless({ 'engine' => $engine,
		       'mux' => $engine->{'mux'},
		       'socket' => $socket,
		       'requests' => 0,
		       'responses' => 0 }, $class);

    $self->{'mux'}->listen($socket);
    $self->{'mux'}->set_callback_object($self, $socket);

    return $self;
}

sub log($$;$) {
    my ($self, $str, $extra_prefix) = @_;

    $self->{'engine'}->log($self, 'SRV: ' . ($extra_prefix || ''), $str);
}

sub shutdown($) {
    my ($self) = @_;

    $self->{'mux'}->close($self->{'socket'});
    delete $self->{'socket'};
}

sub mux_connection($$$) {
    my ($self, $mux, $fh) = @_;

    $self->log('CONNECT');
    my $connection = Varnish::Test::Server::Connection->new($self, $fh);
}

sub mux_close($$) {
    my ($self, $mux, $fh) = @_;

    $self->log('CLOSE');
    delete $self->{'socket'} if $fh == $self->{'socket'};
}

sub got_request($$) {
    my ($self, $connection, $request) = @_;

    $self->{'requests'} += 1;
    $self->log($request->as_string, 'Rx| ');
    $self->{'engine'}->ev_server_request($self, $connection, $request);
}

package Varnish::Test::Server::Connection;

use strict;

sub new($$) {
    my ($this, $server, $fh) = @_;
    my $class = ref($this) || $this;

    my $self = bless({ 'server' => $server,
		       'fh' => $fh,
		       'mux' => $server->{'mux'},
		       'data' => '' }, $class);
    $self->{'mux'}->set_callback_object($self, $fh);
    return $self;
}

sub send_response($$) {
    my ($self, $response) = @_;

    $self->{'mux'}->write($self->{'fh'}, $response->as_string);
    $self->{'server'}->{'responses'} += 1;
    $self->{'server'}->log($response->as_string, 'Tx| ');
}

sub shutdown($) {
    my ($self) = @_;

    $self->{'mux'}->shutdown($self->{'fh'}, 1);
}

sub mux_input($$$$) {
    my ($self, $mux, $fh, $data) = @_;

    while ($$data =~ /\n\r?\n/) {
	my $request = HTTP::Request->parse($$data);
	my $content_ref = $request->content_ref;
	my $content_length = $request->content_length;

	if (defined($content_length)) {
	    my $data_length = length($$content_ref);
	    if ($data_length == $content_length) {
		$$data = '';
		$self->{'server'}->got_request($self, $request);
	    }
	    elsif ($data_length < $content_length) {
		last;
	    }
	    else {
		$$data = substr($$content_ref, $content_length,
				$data_length - $content_length, '');
		$self->{'server'}->got_request($self, $request);
	    }
	}
	else {
	    $$data = $$content_ref;
	    $$content_ref = '';
	    $self->{'server'}->got_request($self, $request);
	}
    }
}

sub mux_eof($$$$) {
    my ($self, $mux, $fh, $data) = @_;

    die 'Junk or incomplete request\n'
	unless $$data eq '';
}

1;
