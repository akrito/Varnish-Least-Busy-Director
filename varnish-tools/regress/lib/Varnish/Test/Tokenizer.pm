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

package Varnish::Test::Tokenizer;

use strict;
use Varnish::Test::Token;

sub new($$) {
    my $this = shift;
    my $class = ref($this) || $this;

    my $self = {};
    bless($self, $class);
    $self->tokenize($_[0])
	if (@_);

    return $self;
}

sub tokenize($$) {
    my $self = shift;
    my $fn = shift;

    local *FILE;
    local $/;

    $self->{'fn'} = $fn;
    $self->{'tokens'} = ();

    open(FILE, "<", $self->{'fn'})
	or die("$self->{'fn'}: $!\n");
    my $spec = <FILE>;
    close(FILE);

    # tokenize
    my @tokens = ();
    for (;;) {
	my $type = undef;
	if ($spec =~ m/\G\s*$/gc) {
	    # EOF
	    push(@tokens, Varnish::Test::Token::EOF->new(pos($spec)));
	    last;
	} elsif ($spec =~ m/\G\s*(\*\/\*([^\*]|\*[^\/])+\*\/)/gc) {
	    # multiline comment
	} elsif ($spec =~ m/\G\s*((?:\/\/|\#).*?)\n/gc) {
	    # single-line comment
	} elsif ($spec =~ m/\G\s*\b(\d+\.\d+)\b/gc) {
	    # real literal
	    push(@tokens, Varnish::Test::Token::Real->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*\b(\d+)\b/gc) {
	    # integer literal
	    push(@tokens, Varnish::Test::Token::Integer->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*\"((?:\\.|[^\"])*)\"/gc) {
	    # string literal
	    push(@tokens, Varnish::Test::Token::String->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*\b(accelerator|client|init|server|case|test|ticket)\b/gc) {
	    # keyword
	    push(@tokens, Varnish::Test::Token::Keyword->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*\b(\w+)\b/gc) {
	    # identifier
	    push(@tokens, Varnish::Test::Token::Identifier->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*(\{)/gc) {
	    # opening brace
	    push(@tokens, Varnish::Test::Token::LeftBrace->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*(\})/gc) {
	    # closing brace
	    push(@tokens, Varnish::Test::Token::RightBrace->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*(\()/gc) {
	    # opening paren
	    push(@tokens, Varnish::Test::Token::LeftParen->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*(\))/gc) {
	    # closing paren
	    push(@tokens, Varnish::Test::Token::RightParen->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*(\;)/gc) {
	    # semicolon
	    push(@tokens, Varnish::Test::Token::SemiColon->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*(\.)/gc) {
	    # period
	    push(@tokens, Varnish::Test::Token::Period->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*(\,)/gc) {
	    # comma
	    push(@tokens, Varnish::Test::Token::Comma->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*([\<\>\=\!]=)/gc) {
	    # comparison operator
	    push(@tokens, Varnish::Test::Token::Compare->new(pos($spec), $1));
	} elsif ($spec =~ m/\G\s*([\+\-\*\/]?=)/gc) {
	    # assignment operator
	    push(@tokens, Varnish::Test::Token::Assign->new(pos($spec), $1));
#	} elsif ($spec =~ m/\G\s*([\+\-\*\/])/gc) {
#	    # arithmetic operator
#	    push(@tokens, Varnish::Test::Token::ArOp->new(pos($spec), $1));
	} else {
	    die "$self->{'fn'}: syntax error\n" . substr($spec, pos($spec)) . "\n";
	}
    }

    $self->{'tokens'} = \@tokens;
    return @tokens;
}

sub die($$) {
    my $self = shift;
    my $msg = shift;

    CORE::die("$self->{'fn'}: $msg\n");
}

sub warn($$) {
    my $self = shift;
    my $msg = shift;

    CORE::warn("$self->{'fn'}: $msg\n");
}


# Return the next token from the input queue, but do not remove it
# from the queue.  Fatal if the queue is empty.
sub peek($) {
    my $self = shift;

    $self->die("premature end of input")
	unless @{$self->{'tokens'}};
    return $self->{'tokens'}->[0];
}

# Remove the next token from the input queue and return it.
# Additional (optional) arguments are token types which the next token
# must match.  Fatal if the queue is empty, or arguments were provided
# but none matched.
sub shift($;@) {
    my $self = CORE::shift;
    my @expect = @_;

    $self->die("premature end of input")
	unless @{$self->{'tokens'}};
    my $token = shift @{$self->{'tokens'}};
    if (@expect) {
	return $token
	    if grep({ $token->is($_) } @expect);
	$self->die("expected " . join(", ", @expect) . ", got " . $token->type);
    }
    return $token;
}

# As shift(), but next token must be a keyword and the arguments are
# matched against the token's value rather than its type.
sub shift_keyword($@) {
    my $self = CORE::shift;
    my @expect = @_;

    my $token = $self->shift("Keyword");
    return $token
	if grep({ $token->value eq $_ } @expect);
    $self->die("expected " . join(", ", @expect) . ", got " . $token->value);
}

1;
