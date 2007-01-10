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

package Varnish::Test::Token;

use strict;

# Common constructor
sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $pos = shift;

    my $self = {
	'pos'	=> $pos,
	'value'	=> '???',
    };
    bless($self, $class);

    # hack: use eval to avoid clobbering @_
    eval { ($self->{'type'} = $class) =~ s/^(\w+::)*(\w+)$/$2/; };

    $self->init(@_);

    return $self;
}

# Default initializer
sub init($;$) {
    my $self = shift;

    $self->value(@_);
}

sub type($;$) {
    my $self = shift;

    $self->{'type'} = shift
	if (@_);
    return $self->{'type'};
}

sub value($;$) {
    my $self = shift;

    $self->{'value'} = shift
	if (@_);
    return $self->{'value'};
}

sub is($$) {
    my $self = shift;
    my $type = shift;

    return ($self->{'type'} eq $type);
}

sub equals($$) {
    my $self = shift;
    my $other = shift;

    return ($self->type() eq $other->type() &&
	    $self->value() eq $other->value());
}

package Varnish::Test::Token::Assign;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::Comma;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::Compare;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::EOF;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::Identifier;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::Integer;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::Keyword;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::LeftBrace;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::LeftParen;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::Period;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::Real;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::RightBrace;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::RightParen;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::SemiColon;

use strict;
use base 'Varnish::Test::Token';

package Varnish::Test::Token::String;

use strict;
use base 'Varnish::Test::Token';

1;
