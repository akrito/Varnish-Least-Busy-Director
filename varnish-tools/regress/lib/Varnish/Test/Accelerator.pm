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

package Varnish::Test::Accelerator;

use strict;
use base 'Varnish::Test::Object';
use IO::Pipe;
use POSIX;

sub _init($) {
    my $self = shift;

    &Varnish::Test::Object::_init($self);

    # Default address / port
    $self->vars->{'address'} = 'localhost';
    $self->vars->{'port'} = '8001';
}

use Data::Dumper;

sub start($) {
    my $self = shift;

    my $backend = $self->vars->{'backend'};
    (defined($backend) &&
     $backend->isa('Varnish::Test::Server'))
	or die("invalid server\n");

    my $stdin = new IO::Pipe;
    my $stdout = new IO::Pipe;
    my $stderr = new IO::Pipe;
    my $pid = fork();
    if (!defined($pid)) {
	# fail
	die("fork(): $!\n");
    } elsif ($pid == 0) {
	# child
	$stdin->reader;
	$stdout->writer;
	$stderr->writer;

	POSIX::dup2($stdin->fileno, 0);
	$stdin->close;
	POSIX::dup2($stdout->fileno, 1);
	$stdout->close;
	POSIX::dup2($stderr->fileno, 2);
	$stderr->close;
	# XXX must be in path
	$ENV{'PATH'} = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';
	exec('varnishd',
	     '-d', '-d',
	     '-a', $self->get('address') . ":" . $self->get('port'),
	     '-b', $backend->get('address') . ":" . $backend->get('port'));
	exit(1);
    }
    # parent

    $stdin->writer;
    $stdout->reader;
    $stderr->reader;

    $self->{'pid'} = $pid;
    $self->{'stdin'} = $stdin;
    $self->{'stdout'} = $stdout;
    $self->{'stderr'} = $stderr;

    # IO::Multiplex is going to issue some warnings here, because it
    # does not handle non-socket file descriptors gently.

    my $mux = $self->get_mux;
    $mux->add($stdin);
    $mux->set_callback_object($self, $stdin);
    $mux->add($stdout);
    $mux->set_callback_object($self, $stdout);
    $mux->add($stderr);
    $mux->set_callback_object($self, $stderr);

    if ($self->has('vcl')) {
	my $vcl = $self->get('vcl');
	$vcl =~ s/\n/ /g;
	$mux->write($stdin, "vcl.inline main " . $vcl . "\n");
    }
}

sub stop($) {
    my $self = shift;

    my $mux = $self->get_mux;

    foreach my $k ('stdin', 'stdout', 'stderr') {
	if (defined($self->{$k})) {
	    $mux->close($self->{$k});
	    delete $self->{$k};
	}
    }
    sleep(1);
    kill(15, $self->{'pid'})
	if ($self->{'pid'});
    delete($self->{'pid'});
}

sub run($) {
    my $self = shift;

    return if $self->{'finished'} or defined($self->{'pid'});

    &Varnish::Test::Object::run($self);

    $self->start;
    $self->{'finished'} = 0;
}

sub shutdown($) {
    my $self = shift;

    $self->stop;
}

sub mux_input($$$$) {
    my $self = shift;
    my $mux = shift;
    my $fh = shift;
    my $data = shift;

    print STDERR $$data;

    if ($$data =~ /vcl.inline/) {
	$mux->write($self->{'stdin'}, "start\n");
    }

    my $started = ($$data =~ /Child starts/);
    $$data = '';

    if ($started) {
	$self->{'finished'} = 1;
	$self->super_run;
    }
}

sub mux_eof($$$$) {
    my $self = shift;
    my $mux = shift;
    my $fh = shift;
    my $data = shift;

    $mux->close($fh);
    foreach my $k ('stdin', 'stdout', 'stderr') {
	if (defined($self->{$k}) && $self->{$k} == $fh) {
	    delete $self->{$k};
	}
    }
}

1;
