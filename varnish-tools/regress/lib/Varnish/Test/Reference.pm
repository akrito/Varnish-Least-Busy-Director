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

package Varnish::Test::Reference;

use strict;

sub new($$) {
    my $this = shift;
    my $class = ref($this) || $this;
    my $symbols = shift;

    my $self = {
	'symbols' => $symbols,
    };
    bless($self, $class);

    return $self;
}

sub as_string($) {
    my $self = shift;
    return join('.', @{$self->{'symbols'}});
}

sub _find_context($$) {
    my $self = shift;
    my $context = shift;

    foreach my $symbol (@{$self->{'symbols'}}[0..$#{$self->{'symbols'}}-1]) {
	$context = $context->get($symbol);
	if (!(ref($context) =~ /^Varnish::Test::\w+$/
	      && $context->isa('Varnish::Test::Context'))) {
	    return undef;
	}
    }

    return $context;
}

sub get_value($$) {
    my $self = shift;
    my $context = shift;

    $context = $self->_find_context($context);
    if (defined($context)) {
	return $context->get($self->{'symbols'}[$#{$self->{'symbols'}}]);
    }
    else {
	return undef;
    }
}

sub set_value($$) {
    my $self = shift;
    my $context = shift;
    my $value = shift;

    $context = $self->_find_context($context);
    if (defined($context)) {
	$context->set($self->{'symbols'}[$#{$self->{'symbols'}}], $value);
    }
    else {
	die "Cannot find containing context for ", join('.', @{$self->{'symbols'}}), ".\n";
    }
}

sub get_function($$) {
    my $self = shift;
    my $context = shift;

    $context = $self->_find_context($context);
    if (defined($context)) {
	return ($context->get($self->{'symbols'}[$#{$self->{'symbols'}}]), $context);
    }
}

1;
