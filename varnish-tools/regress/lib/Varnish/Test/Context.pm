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

package Varnish::Test::Context;

use strict;

#
# A Context is an object that has a name, a type, and a set of named
# variables and procedures associated with it.  A context may have a
# parent, from which it inherits variables and procedures.
#

sub new($$;$) {
    my $this = shift;
    my $class = ref($this) || $this;
    my $name = shift;
    my $parent = shift;

    my $self = {
	'name'		=> $name,
	'vars'		=> { },
    };
    bless($self, $class);

    $self->set_parent($parent);

    return $self;
}

sub set_parent($$) {
    my $self = shift;
    my $parent = shift;

    if (defined($self->{'name'})) {
	if (defined($self->{'parent'})) {
	    # Unlink from old parent.
	    $self->{'parent'}->unset($self->{'name'});
	}
	if (defined($parent)) {
	    # Link to new parent.
	    $parent->set($self->{'name'}, $self);
	}
    }

    $self->{'parent'} = $parent;
}

sub parent($) {
    my $self = shift;

    return $self->{'parent'};
}

sub vars($) {
    my $self = shift;

    return $self->{'vars'};
}

sub set($$$) {
    my $self = shift;
    my $key = shift;
    my $value = shift;

    if (!exists($self->vars->{$key}) &&
	$self->parent && $self->parent->has($key)) {
	$self->parent->set($key, $value);
    } else {
	$self->vars->{$key} = $value;
    }
    return $value;
}

sub unset($$) {
    my $self = shift;
    my $key = shift;

    delete $self->vars->{$key} if exists($self->vars->{$key});
}

sub has($$) {
    my $self = shift;
    my $key = shift;

    return exists($self->{'vars'}->{$key}) ||
	$self->parent && $self->parent->has($key);
}

sub get($$) {
    my $self = shift;
    my $key = shift;

    return exists($self->vars->{$key}) ? $self->vars->{$key} :
	($self->parent && $self->parent->get($key));
}

sub type($) {
    my $self = shift;

    if (!defined($self->{'type'})) {
	($self->{'type'} = ref($self)) =~ s/^(\w+::)*(\w+)$/$2/;
	print STDERR "$self->{'type'}\n";
    }
    return $self->{'type'};
}

sub name($;$) {
    my $self = shift;

    $self->{'name'} = shift
	if (@_);
    return $self->{'name'};
}

1;
