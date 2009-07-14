
use Test::More tests => 4;
BEGIN { use_ok('Varnish::API') };
use Devel::Peek;

use Sys::Hostname qw(hostname);

my $host = hostname;


my $vd = Varnish::API::VSL_New();
Varnish::API::VSL_OpenLog($vd, $host);

Varnish::API::VSL_Dispatch($vd, sub { ok(1); return 1});

{
  my $i = 0;
  Varnish::API::VSL_Dispatch($vd, sub {
			       ok(1);
			       return $i++;
			     });
}

