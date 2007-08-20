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

Varnish::Test::Engine - select-loop wrapper and event dispatcher

=head1 DESCRIPTION

Varnish::Test::Engine is primarily a wrapper around a
IO::Multiplex-based select-loop which monitors activity on
client-side, server-side and Varnish's I/O-channels. On startup, it
automatically creates an associated Server object and a Varnish
objects whoses sockets/filehandles are registered in the
IO::Multiplex-object.

Additionally, event dispatching is performed by the AUTOLOAD method.

=cut

package Varnish::Test::Engine;

use strict;

use Varnish::Test::Server;
use Varnish::Test::Varnish;
use IO::Multiplex;

sub new($$;%) {
    my ($this, $controller, %config) =  @_;
    my $class = ref($this) || $this;

    %config = ('varnish_address' => 'localhost:8080',
	       'server_address' => 'localhost:8081',
	       'telnet_address' => 'localhost:8082',
	       'varnish_name' => 'regress',
	       'storage_spec' => 'file,regress.bin,512k',
	       %config);

    my $self = bless({ 'mux' => IO::Multiplex->new,
		       'controller' => $controller,
		       'config' => \%config,
		       'clients' => [],
		       'pending' => [] }, $class);

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

sub run_loop($@) {
    my ($self, @wait_for) = @_;

    # Sanity-check to help the novice test-case writer.
    die "Engine::run_loop: Already inside select-loop. Your code is buggy.\n"
	if exists($self->{'in_loop'});

    # We need to wait for at least one event.
    die "Engine::run_loop: No events to wait for.\n"
	if @wait_for == 0;

    # Check the queue for pending events which occurred between the
    # last pausing event and the time the loop actually paused. If we
    # are waiting for any of these events (which already occurred),
    # return the first one we find immediately.
    while (@{$self->{'pending'}} > 0) {
	my ($event, @args) = @{shift @{$self->{'pending'}}};
	return ($event, @args) if grep({ $_ eq $event } @wait_for);
    }

    # At this point, the queue of pending events is always empty.
    # Prepare and run IO::Multiplex::loop.

    $self->{'wait_for'} = \@wait_for;
    $self->{'in_loop'} = 1;
    eval { $self->{'mux'}->loop; };
    delete $self->{'in_loop'};
    delete $self->{'wait_for'};
    if ($@) {
	$self->log($self, 'ENG: ', 'IO::Multiplex INCONSISTENT AFTER UNCONTROLLED die().');
	# Maybe we should just exit() here, since we cannot do much
	# useful with an inconsistent IO::Multiplex object.
	die $@;
    }

    # Loop has now been paused due to the occurrence of an event we
    # were waiting for, or a controlled die(). The event is always
    # found in the front of the pending events queue at this point, so
    # return it, or die() if we find a "die event".
    if (@{$self->{'pending'}} > 0) {
	my ($event, @args) = @{shift @{$self->{'pending'}}};
	die $args[0] if ($event eq 'die');
	return ($event, @args);
    }

    # Hm... we should usually not reach this point. The pending queue
    # is empty. Either someone (erroneously) requested a loop pause by
    # calling IO::Multiplex::endloop and forgot to put any event in
    # the queue, or the loop ended itself because all registered
    # filehandles/sockets closed.
    return undef;
}

sub shutdown($) {
    my ($self) = @_;

    # Shutdown varnish and server.
    $self->{'varnish'}->shutdown if defined $self->{'varnish'};
    $self->{'server'}->shutdown if defined $self->{'server'};

    # Close any lingering sockets registered with IO::Multiplex.
    foreach my $fh ($self->{'mux'}->handles) {
	$self->{'mux'}->close($fh);
    }
}

sub AUTOLOAD ($;@) {
    my ($self, @args) = @_;

    (my $event = our $AUTOLOAD) =~ s/.*://;

    return if $event eq 'DESTROY';

    # For the sake of readability, we want all method names we handle
    # to start with "ev_".
    die sprintf("Unknown method '%s'\n", $event)
	unless $event =~ /^ev_(.*)$/;

    $self->log($self, 'ENG: ', sprintf('EVENT "%s"', $1));

    eval {
	# Check to see if the active case object defines an event
	# handler for this event. If so, call it and bring the event
	# arguments along. This will also replace @args, which is
	# significant if this event will pause and return.
	@args = $self->{'case'}->$event(@args)
	    if (defined($self->{'case'}) and $self->{'case'}->can($event));
    };
    if ($@) {
	# The event handler issued die(), which we want to control
	# because we do not want the IO::Multiplex-loop to be subject
	# to it. Hence, we queue it as a special event which will be
	# recognized outside the loop and reissued there, using die().
	# We put this die-event in the front of the queue, using
	# "unshift", so we get it through before any other events
	# already in the queue. Then, signal pause of loop.
	unshift(@{$self->{'pending'}}, [ 'die', $@ ]);
	$self->{'mux'}->endloop;
    }
    elsif (@{$self->{'pending'}} > 0) {
	# Pending event queue is NOT empty, meaning this is an event
	# arriving after a pausing (wait_for) event, but before the
	# pause is in effect. We queue this event unconditionally
	# because it might be the one we are waiting for on the next
	# call to run_loop.
 	push(@{$self->{'pending'}}, [ $event, @args ]);
    }
    elsif (grep({ $_ eq $event} @{$self->{'wait_for'}}) > 0) {
	# Pending event queue is empty and this event is one of those
	# we are waiting for, so put it in the front of the queue and
	# signal loop pause by calling IO::Multiplex::endloop.
	push(@{$self->{'pending'}}, [ $event, @args ]);
	$self->{'mux'}->endloop;
    }
}

1;
