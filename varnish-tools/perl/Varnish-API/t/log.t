
use Test::More tests => 2;
BEGIN { use_ok('Varnish::API') };
use Devel::Peek;
my $vd = Varnish::API::VSL_New;

#print Dump($vd);
my $foo =  Varnish::API::VSL_Name();

Varnish::API::VSL_OpenLog($vd, "varnish1");

my $blah = \$vd;


my $i = 1;
while(1) { 
	 Varnish::API::VSL_Dispatch($vd, sub {});
	 $i++;
	 unless($i % 10000) { print "$i\n" }
}


#ub { print join(" -- ", @_); print "\n"}) }

#for(1..100) { 
#print Dump($blah);
#my $blah = Varnish::API::VSL_NextLog($vd);
#print Dump($blah);
#print "$blah\n";
#}
