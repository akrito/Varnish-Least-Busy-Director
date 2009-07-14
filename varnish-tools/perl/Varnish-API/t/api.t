

#!/usr/bin/perl

use strict;
use warnings;


use Test::More tests => 4;
BEGIN { use_ok('Varnish::API') };
use Devel::Peek;

use Sys::Hostname qw(hostname);

my $vd = Varnish::API::VSL_New();
Varnish::API::VSL_OpenLog($vd, hostname);

Varnish::API::VSL_NonBlocking($vd, 1);
ok(1);
Varnish::API::VSL_NonBlocking($vd, 2);
ok(1);
ok(1, Varnish::API::VSL_Name);

