#!/usr/bin/perl -Tw
#-
# Copyright (c) 2007 Linpro AS
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

package Varnish::Test::Parser;

use strict;

use Parse::RecDescent;
use Varnish::Test::Reference;
use Varnish::Test::Expression;
use Varnish::Test::Statement;
use Varnish::Test::Client;
use Varnish::Test::Server;
use Varnish::Test::Accelerator;
use Varnish::Test::Case;

sub new {
    return new Parse::RecDescent(<<'EOG');

STRING_LITERAL:
	  { extract_delimited($text, '"') }

IDENTIFIER:
	  /[a-z]\w*/i

CONSTANT:
	  /[+-]?(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?/

reference:
	  <leftop: IDENTIFIER '.' IDENTIFIER>
		{ new Varnish::Test::Reference($item[1]) }

argument_list:
	  <leftop: expression ',' expression>

call:
	  reference '(' argument_list(?) ')'
		{ new Varnish::Test::Expression([$item[1], (@{$item[3]}) ? $item[3][0] : []]) }
	| <error>

primary_expression:
	  call
	| reference
	| STRING_LITERAL
	| CONSTANT
	| '(' expression ')'
		{ $item[2] }

mul_op:
	  '*' | '/' | '%'

multiplicative_expression:
	  <leftop: primary_expression mul_op primary_expression>
		{ new Varnish::Test::Expression($item[1]) }

add_op:
	  '+' | '-' | '.'

additive_expression:
	  <leftop: multiplicative_expression add_op multiplicative_expression>
		{ new Varnish::Test::Expression($item[1]) }

rel_op:
	  '==' | '!=' | '<=' | '>=' | '<' | '>'

expression:
	  additive_expression rel_op additive_expression
		{ new Varnish::Test::Expression([@item[1..$#item]], 1) }
	| additive_expression
		{ new Varnish::Test::Expression([$item[1]], 1) }
	| <error>

statement:
	  reference '=' expression
		{ new Varnish::Test::Statement([@item[1..3]]) }
	| call
		{ new Varnish::Test::Statement([$item[1]]) }

block:
	  '{' statement(s? /;/) (';')(?) '}'
		{ $item[2] }
	| <error>

object:
	  'ticket' CONSTANT ';'
		{ [@item[1,2]] }
	| 'client' IDENTIFIER block
		{ new Varnish::Test::Client(@item[2,3]) }
	| 'server' IDENTIFIER block
		{ new Varnish::Test::Server(@item[2,3]) }
	| 'accelerator' IDENTIFIER block
		{ new Varnish::Test::Accelerator(@item[2,3]) }
	| 'case' IDENTIFIER block
		{ new Varnish::Test::Case(@item[2,3]) }
	| <error>

module:
	  'test' STRING_LITERAL(?) '{' object(s?) '}' /^\Z/
		{ { 'id' => (@{$item[2]}) ? $item[2][0] : undef,
		    'body' => $item[4] } }
	| <error>

EOG
}

1;
