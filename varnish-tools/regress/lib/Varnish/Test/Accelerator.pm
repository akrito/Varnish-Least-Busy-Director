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
use POSIX;

sub _init($) {
    my $self = shift;

    # Default address / port
    $self->vars->{'address'} = 'localhost';
    $self->vars->{'port'} = '8001';
}

sub start($) {
    my $self = shift;

    my $backend = $self->vars->{'backend'};
    (defined($backend) &&
     $backend->isa('Varnish::Test::Server'))
	or die("invalid server\n");

    my ($stdinx, $stdin) = POSIX::pipe()
	or die("pipe(): $!\n");
    my ($stdout, $stdoutx) = POSIX::pipe()
	or die("pipe(): $!\n");
    my ($stderr, $stderrx) = POSIX::pipe()
	or die("pipe(): $!\n");
    my $pid = fork();
    if (!defined($pid)) {
	# fail
	die("fork(): $!\n");
    } elsif ($pid == 0) {
	# child
	POSIX::dup2($stdinx, 0);
	POSIX::close($stdin);
	POSIX::close($stdinx);
	POSIX::dup2($stdoutx, 1);
	POSIX::close($stdout);
	POSIX::close($stdoutx);
	POSIX::dup2($stderrx, 2);
	POSIX::close($stderr);
	POSIX::close($stderrx);
	# XXX must be in path
	exec('varnishd',
	     '-d', '-d',
	     '-b', $backend->get('address') . ":" . $backend->get('port'));
	exit(1);
    }
    # parent
    $self->{'pid'} = $pid;
    $self->{'stdin'} = $stdin;
    POSIX::close($stdinx);
    $self->{'stdout'} = $stdout;
    POSIX::close($stdoutx);
    $self->{'stderr'} = $stderr;
    POSIX::close($stderrx);
}

sub stop($) {
    my $self = shift;

    POSIX::close($self->{'stdin'})
	if ($self->{'stdin'});
    POSIX::close($self->{'stdout'})
	if ($self->{'stdout'});
    POSIX::close($self->{'stderr'})
	if ($self->{'stderr'});
    sleep(1);
    kill(15, $self->{'pid'})
	if ($self->{'pid'});
    delete($self->{'stdin'});
    delete($self->{'stdout'});
    delete($self->{'stderr'});
    delete($self->{'pid'});
}

1;
