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
use base 'Varnish::Test::Object';
use Varnish::Test::Accelerator;
use Varnish::Test::Case;
use Varnish::Test::Client;
use Varnish::Test::Server;
use Varnish::Test::Parser;
use IO::Multiplex;

use Data::Dumper;

sub new($;$) {
    my $this = shift;
    my $class = ref($this) || $this;
    my $fn = shift;

    my $self = new Varnish::Test::Object;
    bless($self, $class);

    $self->{'mux'} = new IO::Multiplex;

    if ($fn) {
	$self->parse($fn);
    }

    return $self;
}

sub parse($$) {
    my $self = shift;
    my $fn = shift;

    local $/;
    open(SRC, "<", $fn) or die("$fn: $!\n");
    my $src = <SRC>;
    close(SRC);

    $::RD_HINT = 1;
    my $parser = new Varnish::Test::Parser;
    if (!defined($parser)) {
	die("Error generating parser.");
    }
    my $tree = $parser->module($src);
    if (!defined($tree)) {
	die("Parsing error.");
    }

    print STDERR "###### SYNTAX TREE BEGIN ######\n";
    print STDERR Dumper $tree if defined($tree->{'body'});
    print STDERR "###### SYNTAX TREE END ######\n";

    $self->{'objects'} = [];

    foreach my $object (@{$tree->{'body'}}) {
	if (ref($object) eq 'ARRAY') {
	    $self->{$$object[0]} = $$object[1];
	}
	elsif (ref($object)) {
	    push(@{$self->{'children'}}, $object);
	    $object->set_parent($self);
	}
    }
}

sub main($) {
    my $self = shift;

    while (!$self->{'finished'}) {
	&Varnish::Test::Object::run($self);
	print STDERR "Entering IO::Multiplex loop.\n";
	$self->{'mux'}->loop;
    }

    print STDERR "DONE.\n";
}

sub run($) {
    my $self = shift;

    return if $self->{'finished'};

    &Varnish::Test::Object::run($self);

    $self->shutdown if $self->{'finished'};
}

1;
