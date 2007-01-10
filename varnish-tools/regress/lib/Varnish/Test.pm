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

package Varnish::Test;

use strict;
use base 'Varnish::Test::Context';
use Varnish::Test::Accelerator;
use Varnish::Test::Case;
use Varnish::Test::Client;
use Varnish::Test::Server;
use Varnish::Test::Tokenizer;

sub new($;$) {
    my $this = shift;
    my $class = ref($this) || $this;

    my $self = Varnish::Test::Context->new();
    bless($self, $class);
    $self->parse($_[0])
	if (@_);

    return $self;
}

sub _parse_ticket($$) {
    my $self = shift;
    my $t = shift;

    $t->shift_keyword("ticket");
    push(@{$self->{'ticket'}}, $t->shift("Integer"));
    $t->shift("SemiColon");
}

sub _parse_test($$) {
    my $self = shift;
    my $t = shift;

    my $token = $t->shift_keyword("test");
    $token = $t->shift("String");
    $self->{'descr'} = $token->value;
    $token = $t->shift("LeftBrace");
    for (;;) {
	$token = $t->peek();
	last if $token->is("RightBrace");
	if (!$token->is("Keyword")) {
	    $t->die("expected keyword, got " . ref($token));
	} elsif ($token->value eq 'ticket') {
	    $self->_parse_ticket($t);
	} elsif ($token->value eq 'accelerator') {
	    my $x = Varnish::Test::Accelerator->new($self, $t);
	    $t->die("duplicate declaration of " . $x->name)
		if exists($self->{'vars'}->{$x->name});
	    $self->set($x->name, $x);
	} elsif ($token->value eq 'client') {
	    my $x = Varnish::Test::Client->new($self, $t);
	    $t->die("duplicate declaration of " . $x->name)
		if exists($self->{'vars'}->{$x->name});
	    $self->set($x->name, $x);
	} elsif ($token->value eq 'server') {
	    my $x = Varnish::Test::Server->new($self, $t);
	    $t->die("duplicate declaration of " . $x->name)
		if exists($self->{'vars'}->{$x->name});
	    $self->set($x->name, $x);
	} elsif ($token->value eq 'case') {
	    my $x = Varnish::Test::Case->new($self, $t);
	} else {
	    $t->die("unexpected keyword " . $token->value);
	}
    }
    $token = $t->shift("RightBrace");
}

sub parse($$) {
    my $self = shift;
    my $fn = shift;

    my $t = Varnish::Test::Tokenizer->new($fn);
    $self->_parse_test($t);
}

sub run($) {
    my $self = shift;

}

1;
