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

use IO::Socket::INET;
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
		    '-s', $engine->{'config'}->{'storage_spec'},
		    '-n', $engine->{'config'}->{'varnish_name'},
		    '-a', $engine->{'config'}->{'varnish_address'},
		    '-b', $engine->{'config'}->{'server_address'},
		    '-T', $engine->{'config'}->{'telnet_address'});

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

	# Wait up to 0.5 seconds for Varnish to accept our connection
	# on the management port
	for (my $i = 0; $i < 5; ++$i) {
	    last if $self->{'socket'} = IO::Socket::INET->
		new(Type => SOCK_STREAM,
		    PeerAddr => $engine->{'config'}->{'telnet_address'});
	    select(undef, undef, undef, 0.1);
	}
	if (!defined($self->{'socket'})) {
	    kill(15, delete $self->{'pid'});
	    die "Varnish did not start\n";
	}
	$self->{'mux'}->add($self->{'socket'});
	$self->{'mux'}->set_callback_object($self, $self->{'socket'});
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
    $self->log("sending command: $command");
    $self->{'mux'}->write($self->{'socket'}, $command . "\n");
    $self->{'mux'}->set_timeout($self->{'socket'}, 2);
    $self->{'pending'} = $command;
    my ($ev, $code, $text) =
	$self->{'engine'}->run_loop('ev_varnish_result',
				    'ev_varnish_timeout');
    delete $self->{'pending'};
    return ($code, $text);
}

sub send_vcl($$$) {
    my ($self, $config, $vcl) = @_;

    return $self->send_command('vcl.inline', $config, $vcl);
}

sub use_vcl($$) {
    my ($self, $config) = @_;

    return $self->send_command('vcl.use', $config);
}

sub start_child($) {
    my ($self) = @_;
    die "not ready\n"
	if $self->{'state'} eq "init";
    die "already started\n"
	if $self->{'state'} eq "started";

    return $self->send_command("start");
}

sub stop_child($) {
    my ($self) = @_;
    die "not ready\n"
	if $self->{'state'} eq 'init';
    die "already stopped\n"
	if $self->{'state'} eq 'stopped';

    return $self->send_command("stop");
}

sub set_param($$$) {
    my ($self, $param, $value) = @_;

    return $self->send_command('param.set', $param, $value);
}

sub shutdown($) {
    my ($self) = @_;

    $self->{'mux'}->close(delete $self->{'stdin'})
	if $self->{'stdin'};
    $self->{'mux'}->close(delete $self->{'stdout'})
	if $self->{'stdout'};
    $self->{'mux'}->close(delete $self->{'stderr'})
	if $self->{'stderr'};
    $self->{'mux'}->close(delete $self->{'socket'})
	if $self->{'socket'};
    kill(15, delete $self->{'pid'})
	if $self->{'pid'};
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

    $self->{'mux'}->set_timeout($fh, undef);
    if ($fh == $self->{'socket'}) {
	die "syntax error\n"
	    unless ($$data =~ m/^([1-5][0-9][0-9]) (\d+) *$/m);
	my ($line, $code, $len) = ($&, $1, $2);
	if (length($$data) < length($line) + $len) {
	    # we don't have the full response yet.
	    $self->{'mux'}->set_timeout($fh, 2);
	    return;
	}
	# extract the response text (if any), then remove from $$data
	my $text = substr($$data, length($line), $len);
	substr($$data, 0, length($line) + $len + 1, '');

	$self->{'engine'}->ev_varnish_result($code, $text);
    } else {
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
	# XXX there might be more!
	$$data = '';
    }
}

sub mux_timeout($$$) {
    my ($self, $mux, $fh) = @_;

    $self->{'mux'}->set_timeout($fh, undef);
    $self->shutdown();
    $self->{'engine'}->ev_varnish_timeout($self);
}

1;
