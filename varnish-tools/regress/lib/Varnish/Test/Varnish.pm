#!/usr/bin/perl -w
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

Varnish::Test::Varnish - Varnish child-process controller

=head1 DESCRIPTION

A Varnish::Test::Varnish object is used to fork off a Varnish child
process and control traffic going into and coming out of the Varnish
(management process) command-line interface (CLI).

Various events are generated when certain strings are identified in
the output from the CLI.

=cut

package Varnish::Test::Varnish;

use strict;

use Socket;

sub new($$;$) {
    my ($this, $engine, $attrs) =  @_;
    my $class = ref($this) || $this;

    my $self = bless({ 'engine' => $engine,
		       'mux' => $engine->{'mux'},
		       'state' => 'init' }, $class);

    # Create pipes (actually socket pairs) for communication between
    # parent and child.

    socketpair(STDIN_READ, STDIN_WRITE, AF_UNIX, SOCK_STREAM, PF_UNSPEC);
    shutdown(STDIN_READ, 1);
    shutdown(STDIN_WRITE, 0);
    socketpair(STDOUT_READ, STDOUT_WRITE, AF_UNIX, SOCK_STREAM, PF_UNSPEC);
    shutdown(STDOUT_READ, 1);
    shutdown(STDOUT_WRITE, 0);
    socketpair(STDERR_READ, STDERR_WRITE, AF_UNIX, SOCK_STREAM, PF_UNSPEC);
    shutdown(STDERR_READ, 1);
    shutdown(STDERR_WRITE, 0);

    # Ignore SIGCHLD.
    $SIG{CHLD} = 'IGNORE';

    my $pid = fork;
    die "fork(): $!\n"
	unless defined($pid);

    if ($pid == 0) {
	# Child

	close STDIN_WRITE;
	close STDOUT_READ;
	close STDERR_READ;

	# dup2(2) the I/O-channels to std{in,out,err} and close the
	# original file handles before transforming into Varnish.

	open STDIN, '<&', \*STDIN_READ;
	close STDIN_READ;
	open STDOUT, '>&', \*STDOUT_WRITE;
	close STDOUT_WRITE;
	open STDERR, '>&', \*STDERR_WRITE;
	close STDERR_WRITE;

	my @opts = ('-d', '-d',
		    '-a', $engine->{'config'}->{'varnish_address'},
		    '-b', $engine->{'config'}->{'server_address'});

	print STDERR sprintf("Starting Varnish with options: %s\n", join(' ', @opts));

	# Unset ignoring of SIGCHLD, so Varnish will get signals from
	# its children.

	delete $SIG{CHLD};

	# Transform into Varnish. Goodbye Perl-code!
	exec('varnishd', @opts);
	exit(1);
    }
    else {
	# Parent
	$self->log('PID: ' . $pid);

	close STDIN_READ;
	close STDOUT_WRITE;
	close STDERR_WRITE;

	$self->{'pid'} = $pid;
	$self->{'stdin'} = \*STDIN_WRITE;
	$self->{'stdout'} = \*STDOUT_READ;
	$self->{'stderr'} = \*STDERR_READ;

	# Register the Varnish I/O-channels with the IO::Multiplex
	# loop object.

	$self->{'mux'}->add($self->{'stdin'});
	$self->{'mux'}->set_callback_object($self, $self->{'stdin'});
	$self->{'mux'}->add($self->{'stdout'});
	$self->{'mux'}->set_callback_object($self, $self->{'stdout'});
	$self->{'mux'}->add($self->{'stderr'});
	$self->{'mux'}->set_callback_object($self, $self->{'stderr'});
    }

    return $self;
}

sub log($$) {
    my ($self, $str) = @_;

    $self->{'engine'}->log($self, 'VAR: ', $str);
}

sub backend_block($$) {
    my ($self, $name) = @_;

    return sprintf("backend %s {\n  set backend.host = \"%s\";\n  set backend.port = \"%s\";\n}\n",
		   $name, split(':', $self->{'engine'}->{'config'}->{'server_address'}));
}

sub send_command($@) {
    my ($self, @args) = @_;
    die "not ready\n"
	if $self->{'state'} eq 'init';
    die sprintf("busy awaiting earlier command (%s)\n", $self->{'pending'})
	if defined $self->{'pending'};

    foreach (@args) {
	if (m/[\s\"\n]/) {
	    s/\n/\\n/g;
	    s/\"/\\\"/g;
	    s/^(.*)$/"$1"/g;
	}
    }
    my $command = join(' ', @args);
    $self->{'mux'}->write($self->{'stdin'}, $command . "\n");
    $self->{'pending'} = $command;
}

sub send_vcl($$$) {
    my ($self, $config, $vcl) = @_;

    $self->send_command('vcl.inline', $config, $vcl);
}

sub use_vcl($$) {
    my ($self, $config) = @_;

    $self->send_command('vcl.use', $config);
}

sub start_child($) {
    my ($self) = @_;
    die "not ready\n"
	if $self->{'state'} eq "init";
    die "already started\n"
	if $self->{'state'} eq "started";

    $self->send_command("start");
}

sub stop_child($) {
    my ($self) = @_;
    die "not ready\n"
	if $self->{'state'} eq 'init';
    die "already stopped\n"
	if $self->{'state'} eq 'stopped';

    $self->send_command("stop");
}

sub shutdown($) {
    my ($self) = @_;

    $self->{'mux'}->shutdown(delete $self->{'stdin'}, 1);
}

sub kill($;$) {
    my ($self, $signal) = @_;

    $signal ||= 15;
    die "Not running\n"
	unless defined($self->{'pid'});
    kill($signal, $self->{'pid'});
    delete $self->{'pid'};
}

sub mux_input($$$$) {
    my ($self, $mux, $fh, $data) = @_;

    $self->log($$data);

    if ($$data =~ /^rolling\(2\)\.\.\./m) {
	$self->{'state'} = 'stopped';
	$self->{'engine'}->ev_varnish_started;
    }
    if ($$data =~ /Child starts/) {
	$self->{'state'} = 'started';
	$self->{'engine'}->ev_varnish_child_started;
    }
    if ($$data =~ /Child dies/) {
	$self->{'state'} = 'stopped';
	$self->{'engine'}->ev_varnish_child_stopped;
    }

    $self->{'engine'}->ev_varnish_command_ok(delete $self->{'pending'})
	if ($$data =~ /^200 \d+/m and $self->{'pending'});

    $self->{'engine'}->ev_varnish_command_unknown(delete $self->{'pending'})
	if ($$data =~ /^300 \d+/m and $self->{'pending'});

    $$data = '';
}

1;
