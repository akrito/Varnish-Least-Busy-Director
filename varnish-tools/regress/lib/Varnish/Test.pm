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

=head1 NAME

Varnish::Test - Regression test framework for Varnish

=head1 DESCRIPTION

The varnish regression test framework works by starting up a Varnish
process and then communicating with this process as both client and
server.

=head1 STRUCTURE

When regressions tests start, an instance of Varnish is forked off as
a child process, and its I/O channels (std{in,out,err}) are controlled
by the parent process which also performs the test by playing the role
of both HTTP client and server.

A single select(2)-driven loop is used to handle all activity on both
server and client side, as well on Varnish's I/O-channels. This is
done using IO::Multiplex.

As a result of using a select-loop, the framework has an event-driven
design in order to cope with unpredictable sequence of processing on
either server og client side. To drive a test-case forward, the
select-loop is paused when certain events occur, and control returns
to the "main program" which can then inspect the situation. This
results in certain structural constraints. It is essential to be aware
of whether a piece of code is going to run inside or outside the
select-loop.

The framework uses Perl objects to represent instances of servers and
clients as well as the Varnish instance itself. In addition, there is
an "engine" object which propagates events and controls the program
flow related to the select-loop.

=cut

package Varnish::Test;

use Carp 'croak';

use Varnish::Test::Engine;

sub new($) {
    my ($this) =  @_;
    my $class = ref($this) || $this;

    return bless({ 'cases' => [] }, $class);
}

sub start_engine($;@) {
    my ($self, @args) = @_;

    return if defined $self->{'engine'};
    $self->{'engine'} = Varnish::Test::Engine->new(@args);
    $self->{'engine'}->run_loop('ev_varnish_started');
}

sub stop_engine($;$) {
    my ($self) = @_;

    (delete $self->{'engine'})->shutdown if defined $self->{'engine'};
}

sub run_case($$) {
    my ($self, $name) = @_;

    my $module = 'Varnish::Test::Case::' . $name;

    eval 'use ' . $module;
    croak $@ if $@;

    $self->start_engine;

    my $case = $module->new($self->{'engine'});

    push(@{$self->{'cases'}}, $case);

    $case->init;
    $case->run;
    $case->fini;

    $self->stop_engine;
}

1;
