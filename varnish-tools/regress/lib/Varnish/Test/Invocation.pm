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

package Varnish::Test::Invocation;

use strict;
use base 'Varnish::Test::Object';

sub new($$$) {
    my $this = shift;
    my $class = ref($this) || $this;
    my $func_id = shift;
    my $args = shift;

    my $self = new Varnish::Test::Object(undef, $args);
    bless($self, $class);

    $self->{'func_id'} = $func_id;
    $self->{'args'} = $args;

    return $self;
}

sub run($) {
    my $self = shift;

    return if $self->{'finished'};

    &Varnish::Test::Object::run($self) unless $self->{'in_call'};

    if ($self->{'finished'}) {
	$self->{'finished'} = 0;
	if (!$self->{'in_call'}) {
	    $self->{'in_call'} = 1;
	    my ($func_ptr, $func_context) = $self->{'func_id'}->get_function($self);
	    # print STDERR "Calling " . $self->{'func_id'}->as_string, "\n";
	    &$func_ptr($func_context, $self);
	}
    }
}

1;
