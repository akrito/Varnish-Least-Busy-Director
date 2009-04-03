#!/usr/bin/perl -w
#-
# Copyright (c) 2006-2009 Linpro AS
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

Varnish::Test::Server - HTTP-server emulator

=head1 DESCRIPTION

A Varnish::Test::Server object has the capability of listening on a
TCP socket, receiving HTTP requests and sending responses.

Every established connection is handled by an associated object of
type L<Varnish::Test::Server::Connection>.

=cut

package Varnish::Test::Server;

use strict;

use Varnish::Test::Server::Connection;
use IO::Socket::INET;

=head2 new

Called by a Varnish::Test::Engine object to create a new Server
object. It sets up its listening socket and registers it in Engine's
IO::Multiplex object (mux).

=cut

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

=head2 log

Logging facility.

=cut

sub log($$;$) {
    my ($self, $str, $extra_prefix) = @_;

    $self->{'engine'}->log($self, 'SRV: ' . ($extra_prefix || ''), $str);
}

=head2 logf

Logging facility using a formatting string as first argument.

=cut

sub logf($$;@) {
    my ($self, $fmt, @args) = @_;

    $self->{'engine'}->log($self, 'SRV: ', sprintf($fmt, @args));
}

=head2 shutdown

Called by the main program to terminate the server object and its
listening socket.

=cut

sub shutdown($) {
    my ($self) = @_;

    $self->{'mux'}->close($self->{'socket'});
    delete $self->{'socket'};
}

=head2 got_request

Called by L<Varnish::Test::Server::Connection> object when an HTTP
message has been received. An B<ev_server_request> event is
dispatched.

=cut

sub got_request($$) {
    my ($self, $connection, $request) = @_;

    $self->{'requests'} += 1;
    $self->logf("%s %s %s", $request->method(), $request->uri(), $request->protocol());
    $self->{'engine'}->ev_server_request($self, $connection, $request);
}

=head1 IO::MULTIPLEX CALLBACKS

=head2 mux_connection

Called by L<IO::Multiplex> when the listening socket has received a
new connection. The file-handle of the new connection is provided as
an argument and is given to a newly created
L<Varnish::Test::Server::Connection> object which will operate the new
connection from now on.

=cut

sub mux_connection($$$) {
    my ($self, $mux, $fh) = @_;

    $self->log('CONNECT');
    my $connection = Varnish::Test::Server::Connection->new($self, $fh);
}

=head2 mux_close

Called by L<IO::Multiplex> when the listening socket has been closed.

=cut

sub mux_close($$) {
    my ($self, $mux, $fh) = @_;

    $self->log('CLOSE');
    delete $self->{'socket'} if $fh == $self->{'socket'};
}

1;

=head1 SEE ALSO

L<Varnish::Test::Server::Connection>

=cut
