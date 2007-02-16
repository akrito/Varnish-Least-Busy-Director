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
use base 'Varnish::Test::Object';
use IO::Socket;

sub _init($) {
    my $self = shift;

    &Varnish::Test::Object::_init($self);

    $self->set('address', 'localhost');
    $self->set('port', '9001');
}

sub run($) {
    my $self = shift;

    return if $self->{'finished'};

    &Varnish::Test::Object::run($self);

    my $fh = new IO::Socket::INET(Proto     => 'tcp',
				  LocalAddr => $self->get('address'),
				  LocalPort => $self->get('port'),
				  Listen    => 4)
	or die "socket: $@";

    $self->{'fh'} = $fh;

    my $mux = $self->get_mux;
    $mux->listen($fh);
    $mux->set_callback_object($self, $fh);
}

sub shutdown($) {
    my $self = shift;

    $self->get_mux->close($self->{'fh'});
}

sub mux_connection($$$) {
    my $self = shift;
    my $mux = shift;
    my $fh = shift;

    $mux->set_callback_object($self, $fh);
}

sub mux_input($$$$) {
    my $self = shift;
    my $mux = shift;
    my $fh = shift;
    my $data = shift;

    $$data = ""; # Pretend we read the data.

    my $response = "HTTP/" . eval($self->get('protocol')) . " 200 OK\r\n"
	. "Content-Type: text/plain; charset=utf-8\r\n\r\n"
	. eval($self->get('data')) . "\n";

    $mux->write($fh, $response);
    print STDERR "Server sent: " . $response;
    $mux->shutdown($fh, 1);
}

1;
