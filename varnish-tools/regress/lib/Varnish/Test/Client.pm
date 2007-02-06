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

package Varnish::Test::Client;

use strict;
use base 'Varnish::Test::Object';
use IO::Socket;
use URI;

sub _init($) {
    my $self = shift;

    $self->set('protocol', '1.1');
    $self->set('request', \&request);
}

sub request($$) {
    my $self = shift;
    my $invocation = shift;

    my $server = $invocation->{'args'}[0]->{'return'};
    my $uri = $invocation->{'args'}[1]->{'return'};

    (defined($server) &&
     ($server->isa('Varnish::Test::Accelerator') ||
      $server->isa('Varnish::Test::Server')))
	or die("invalid server\n");

    $uri = new URI($uri)
	or die("invalid URI\n");

    my $fh = new IO::Socket::INET(Proto    => 'tcp',
				  PeerAddr => $server->get('address'),
				  PeerPort => $server->get('port'))
	or die "socket: $@";

    my $mux = $self->get_mux;
    $mux->add($fh);
    $mux->set_callback_object($self, $fh);

    $mux->write($fh, "Hello\r\n");
    print "Client sent: Hello\n";

    $self->{'request'} = $invocation;
}

sub mux_input($$$$) {
    my $self = shift;
    my $mux = shift;
    my $fh = shift;
    my $data = shift;

    $self->{'request'}->{'return'} = $$data;
    print "Client got: $$data";
    $$data = "";
    $self->{'request'}->{'finished'} = 1;
    delete $self->{'request'};
    $self->super_run;
}

sub mux_eof($$$$) {
    my $self = shift;
    my $mux = shift;
    my $fh = shift;
    my $data = shift;

    $mux->close($fh);
}

1;
