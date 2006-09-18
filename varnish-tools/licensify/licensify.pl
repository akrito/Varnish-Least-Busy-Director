#!/usr/bin/perl -w
#-
# Copyright (c) 2006 Verdens Gang AS
# Copyright (c) 2006 Linpro AS
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
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

use strict;
use vars qw($FIRSTYEAR $LICENSE);

$FIRSTYEAR = 2006;

$LICENSE =
"Copyright (c) YYYY Verdens Gang AS
Copyright (c) YYYY Linpro AS
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY AUTHOR AND CONTRIBUTORS ``AS IS'' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
SUCH DAMAGE.

";

sub licensify($) {
    my $fn = shift;

    local *FILE;
    local $/;
    my $contents;
    my $first;
    my $prefix;
    my $license;

    open(FILE, "<", $fn)
	or die("$fn: $!\n");
    $contents = <FILE>;
    close(FILE);

    return unless $contents =~ m/^(\.\\\"|\/\*|\#!\/[^\n]+\n\#)(-?)\n/s;
    return if $2;
    $first = $1;
    if ($first =~ /^\#/) {
	$prefix = "#";
    } elsif ($first =~ /\/\*/) {
	$prefix = " *";
    } else {
	$prefix = $first;
    }
    ($license = $LICENSE) =~ s/^/$prefix /gm;
    $license =~ s/[\t ]+$//gm;
    $contents =~ s/^(\Q$first\E)\n/$1-\n$license/s;

    open(FILE, ">", $fn)
	or die("$fn: $!\n");
    print(FILE $contents);
    close(FILE);
}

MAIN:{
    my @tm = localtime(time());
    my $year = 1900 + $tm[5];
    $year = "$FIRSTYEAR-$year"
	unless ($year == $FIRSTYEAR);
    $LICENSE =~ s/YYYY/$year/g;
    foreach (@ARGV) {
	licensify($_);
    }
}
