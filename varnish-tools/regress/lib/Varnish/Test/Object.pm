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
use Varnish::Test::Code;

sub new($$;$) {
    my $this = shift;
    my $class = ref($this) || $this;
    my $parent = shift;

    my $self = Varnish::Test::Context->new($parent);
    $self->{'code'} = [];
    bless($self, $class);

    $self->_init();

    $self->_parse($_[0])
	if (@_);

    return $self;
}

sub _init($) {
    my $self = shift;

    # nothing
}

sub _parse($$) {
    my $self = shift;
    my $t = shift;

    $t->shift_keyword(lc($self->type));
    $self->name($t->shift("Identifier")->value);
    $t->shift("LeftBrace");
    while (!$t->peek()->is("RightBrace")) {
	push(@{$self->{'code'}}, Varnish::Test::Code->new($self, $t));
# 	$token = $t->shift("Identifier");
# 	my $key = $token->value;
# 	$token = $t->shift("Assign");
# 	$token = $t->shift("Integer", "Real", "String");
# 	my $value = $token->value;
# 	$token = $t->shift("SemiColon");
# 	$t->warn("multiple assignments to $self->{'name'}.$key")
# 	    if ($self->has($key));
# 	$self->set($key, $value);
    }
    $t->shift("RightBrace");
}

1;
