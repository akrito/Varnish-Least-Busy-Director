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

package Varnish::Test::Object;

use strict;
use base 'Varnish::Test::Context';

sub new($$$;$) {
    my $this = shift;
    my $class = ref($this) || $this;
    my $name = shift;
    my $children = shift;
    my $parent = shift;

    my $self = new Varnish::Test::Context($name, $parent);
    bless($self, $class);

    for my $child (@$children) {
	$child->set_parent($self);
    }

    $self->{'children'} = $children;
    $self->{'finished'} = 0;
    $self->{'return'} = undef;
    $self->_init;

    return $self;
}

sub _init($) {
}

sub run($) {
    my $self = shift;

    return if $self->{'finished'};

    foreach my $child (@{$self->{'children'}}) {
	$child->run($self) unless $child->{'finished'};
	return unless $child->{'finished'};
	$self->{'return'} = $child->{'return'};
    }

    $self->{'finished'} = 1;
}

sub shutdown($) {
    my $self = shift;

    foreach my $child (@{$self->{'children'}}) {
	$child->shutdown;
    }
}

sub get_mux($) {
    my $self = shift;
    return $self->{'mux'} || $self->{'parent'} && $self->{'parent'}->get_mux;
}

sub super_run($) {
    my $self = shift;
    if (defined($self->{'parent'})) {
	$self->{'parent'}->super_run;
    }
    else {
	$self->run;
    }
}

1;
