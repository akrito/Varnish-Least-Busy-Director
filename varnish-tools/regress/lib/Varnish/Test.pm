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

Varnish::Test - Regression test framework for Varnish

=head1 DESCRIPTION

The Varnish regression test framework works by starting up a Varnish
process and then communicating with this process as both client and
server.

 +---------------------------------------------------------+
 |                     TEST FRAMEWORK                      |
 |                                                         |
 |                       Controller                        |
 |          +-----------------------------------+          |
 |          |               | C ^               |          |
 |          | configuration | L | status        |          |
 |          |               v I |               |          |
 |          |  requests  +---------+  requests  |          |
 |          | =========> |         | =========> |          |
 | Client   |    HTTP    | VARNISH |    HTTP    | Server   |
 | emulator | <========= |         | <========= | emulator |
 |          |  responses +---------+  responses |          |
 +----------+                                   +----------+

=head1 STRUCTURE

When regression tests start, an instance of Varnish is forked off as a
child process, and its I/O channels (std{in,out,err} which are
connected to the command-line interface of Varnish) are controlled by
the parent process which also performs the tests by playing the role
of both HTTP client and server.

A single select(2)-driven loop is used to handle all activity on both
server and client side, as well on Varnish's I/O-channels. This is
done using L<IO::Multiplex>.

As a result of using a select-loop (as opposed to a multi-threaded or
multi-process approach), the framework has an event-driven design in
order to cope with the unpredictable sequence of I/O on server or
client side (or Varnish's I/O-channels for that matter) . To drive a
test-case forward, the select-loop is paused when certain events
occur, and control returns to the "main program" which can then
inspect the situation. This results in certain structural constraints,
and it is essential to be aware of whether a piece of code is going to
run inside (event handler) or outside (main program) the select-loop.

The framework uses Perl objects to represent instances of servers
(Varnish::Test::Server) and clients (Varnish::Test::Client) as well as
the Varnish instance itself (Varnish::Test::Varnish). In addition,
there is an engine object (Varnish::Test::Engine) which dispatches
events and controls the program flow related to the select-loop.
Futhermore, each test case is represented by an object
(Varnish::Test::Case subclass). HTTP requests and responses are
represented by objects of HTTP::Request and HTTP::Response,
respectively. Finally, there is an overall test-case controller object
(Varnish::Test) which accumulates test-case results.

=head1 EVENT PROCESSING

Events typically occur in the call-back routines (mux_*) of client,
server, and Varnish objects. An event is created by calling an ev_*
method of the engine object. These calls are handled by Perl's
AUTOLOAD mechanism since Engine does not define any ev_* methods
explicitly. The AUTOLOAD routine works as the event dispatcher by
looking for an event handler in the currently running test-case
object, and also determines whether the event being processed is
supposed to pause the select-loop and return control back to the main
program.

=head1 METHODS

=cut

package Varnish::Test;

use Varnish::Test::Case;
use Varnish::Test::Engine;

=head2 new

Create a new Test object.

=cut

sub new($) {
    my ($this) =  @_;
    my $class = ref($this) || $this;

    return bless({ 'cases' => [] }, $class);
}

=head2 start_engine

Creates an associated L<Varnish::Test::Engine> object which in turn
starts an L<IO::Multiplex>, a L<Varnish::Test::server>, and a
L<Varnish::Test::Varnish> object.

=cut

sub start_engine($;@) {
    my ($self, @args) = @_;

    return if defined $self->{'engine'};
    $self->{'engine'} = Varnish::Test::Engine->new(@args);
}

=head2 stop_engine

Stop Engine object using its "shutdown" method which also stops the
server, Varnish, and closes all other open sockets (which might have
been left by client objects that have not been shut down explicitly
during test-case run).

=cut

sub stop_engine($;$) {
    my ($self) = @_;

    if (defined($self->{'engine'})) {
	$self->{'engine'}->shutdown();
	delete $self->{'engine'};
    }
}

=head2 cases

Return a list of Perl modules under Varnish/Test/Case directory. These
are all the available test-cases.

=cut

sub cases($) {
    my ($self) = @_;

    my $dir = $INC{'Varnish/Test/Case.pm'};
    $dir =~ s/\.pm$/\//;
    local *DIR;
    opendir(DIR, $dir)
	or die("$dir: $!\n");
    my @cases = sort grep { s/^(\w+)\.pm$/$1/ } readdir(DIR);
    closedir(DIR);
    return @cases;
}

=head2 run_case

Run a test-case given by its name.

=cut

sub run_case($$) {
    my ($self, $name) = @_;

    my $module = 'Varnish::Test::Case::' . $name;

    eval 'use ' . $module;
    die $@ if $@;

    $self->start_engine();

    my $case = $module->new($self->{'engine'});

    push(@{$self->{'cases'}}, $case);

    eval {
	$case->init();
	$case->run();
	$case->fini();
    };
    if ($@) {
	$self->{'engine'}->log($self, 'TST: ', $@);
	$self->stop_engine();
    }
}

=head2 results

Return a hashref of all test-case results.

=cut

sub results($) {
    my ($self) = @_;

    map { $_->results() } @{$self->{'cases'}};
}

1;

=head1 SEE ALSO

L<Varnish::Test::Engine>
L<Varnish::Test::Server>
L<Varnish::Test::Varnish>
L<Varnish::Test::Case>
L<IO::Multiplex>

=cut
