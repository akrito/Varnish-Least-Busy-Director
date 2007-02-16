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

package Varnish::Test::Expression;

use strict;
use base 'Varnish::Test::Object';
use Varnish::Test::Invocation;

sub new($$;$) {
    my $this = shift;
    my $class = ref($this) || $this;
    my $terms = shift;
    my $force_create = shift;

    if (@$terms == 1 && (!$force_create || ref($$terms[0]) eq $class)) {
	return $$terms[0];
    }

    my $children = [];

    if (@$terms == 2
	&& ref($$terms[0]) eq 'Varnish::Test::Reference'
	&& ref($$terms[1]) eq 'ARRAY') {
	my $invocation = new Varnish::Test::Invocation($$terms[0], $$terms[1]);
	push (@$children, $invocation);
	undef $terms;
    }
    else {
	foreach my $term (@$terms) {
	    push (@$children, $term) if ref($term) eq 'Varnish::Test::Expression';
	}
    }

    my $self = new Varnish::Test::Object(undef, $children);
    bless($self, $class);
    $self->{'terms'} = $terms;

    return $self;
}

sub run($) {
    my $self = shift;

    return if $self->{'finished'};

    &Varnish::Test::Object::run($self);

    my $expr = '';
    my $seen_string = 0;
    my $relational = 0;

    if ($self->{'finished'} && defined($self->{'terms'})) {

	foreach my $term (@{$self->{'terms'}}) {
	    my $term_value;
	    if (ref($term) eq 'Varnish::Test::Expression') {
		$term_value = $term->{'return'};
	    }
	    elsif (ref($term) eq 'Varnish::Test::Reference') {
		$term_value = $term->get_value($self);
		if (!defined($term_value)) {
		    die '"' . $term->as_string . '"' . " not defined";
		}
	    }
	    else {
		if ($term eq '==' || $term eq '!='
		    || $term eq '<=' || $term eq '>='
		    || $term eq '<' || $term eq '>') {
		    $relational = 1;

		    if ($seen_string) {
			if ($term eq '==') {
			    $term = 'eq';
			}
			elsif ($term eq '!=') {
			    $term = 'ne';
			}
		    }
		}
		$term_value = $term;
	    }

	    if (ref(\$term_value) eq 'REF') {
		if (@{$self->{'terms'}} == 1) {
		    $self->{'return'} = $term_value;
		    return;
		}
		else {
		    $term_value = '"' . $term_value . '"';
		}
	    }

	    if ($term_value =~ /^".*"$/s) {
		$seen_string = 1;
	    }

	    $expr .= $term_value;
	}

	($expr) = $expr =~ /(.*)/s;

	# print STDERR "Evaling: $expr\n";

	$expr = eval $expr;

	if ($seen_string && !$relational) {
	    $expr = '"' . $expr . '"';
	}

	$self->{'return'} = $expr;
    }
}

1;
