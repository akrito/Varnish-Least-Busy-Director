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

package Varnish::Test::Engine;

use strict;
use Carp 'croak';

use Varnish::Test::Server;
use Varnish::Test::Varnish;
use Varnish::Test::Client;
use IO::Multiplex;

sub new($$;%) {
    my ($this, $controller, %config) =  @_;
    my $class = ref($this) || $this;

    %config = ('server_address' => 'localhost:8081',
	       'varnish_address' => 'localhost:8080',
	       %config);

    my $self = bless({ 'mux' => IO::Multiplex->new,
		       'controller' => $controller,
		       'config' => \%config }, $class);

    $self->{'server'} = Varnish::Test::Server->new($self);
    $self->{'varnish'} = Varnish::Test::Varnish->new($self);

    return $self;
}

sub log($$$) {
    my ($self, $object, $prefix, $str) = @_;

    $str =~ s/^/$prefix/gm;
    $str =~ s/\n?$/\n/;

    print STDERR $str;
}

sub run_loop($) {
    my ($self) = @_;

    croak 'Engine::run: Already inside select-loop. Your code is buggy.'
      if exists($self->{'in_loop'});

    $self->{'in_loop'} = 1;
    $self->{'mux'}->loop;
    delete $self->{'in_loop'};

    return delete $self->{'return'} if exists $self->{'return'};
    return undef;
}

sub pause_loop($;$) {
    my ($self, $return) = @_;

    croak 'Engine::pause: Not inside select-loop. Your code is buggy.'
      unless exists($self->{'in_loop'});

    $self->{'return'} = $return if defined($return);
    $self->{'mux'}->endloop;
}

sub shutdown($) {
    my ($self) = @_;

    $self->{'varnish'}->shutdown if defined $self->{'varnish'};
    $self->{'server'}->shutdown if defined $self->{'server'};
    foreach my $fh ($self->{'mux'}->handles) {
	$self->{'mux'}->close($fh);
    }
}

sub ev_varnish_started($) {
    my ($self) = @_;

    $self->pause_loop;
}

sub AUTOLOAD ($;@) {
    my ($self, @args) = @_;

    (my $event_handler = our $AUTOLOAD) =~ s/.*://;

    return if $event_handler eq 'DESTROY';

    croak sprintf('received event (%s) while not running a case', $event_handler)
      unless defined $self->{'case'};

    croak sprintf('Unknown method "%s"', $event_handler)
      unless $event_handler =~ /^ev_(.*)$/;

    if ($self->{'case'}->can($event_handler)) {
	$self->log($self, 'ENG: ', sprintf('EVENT "%s"', $1));
	return $self->{'case'}->$event_handler(@args);
    }
    else {
	$self->log($self, 'ENG: ', sprintf('EVENT "%s" IGNORED', $1));
	return undef;
    }
}

1;
