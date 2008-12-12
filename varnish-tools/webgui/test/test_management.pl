use strict;
use warnings;
use Varnish::Management;

my $console = Varnish::Management->new("localhost", "9001");

my $status = $console->set_config("testing", "backend b0 { .host = \"localhost\"; .port = \"8080\"; }");

if ($status ne "") {
	print "Error:\n$status\n";
}

for my $config ($console->get_config_names()) {
	print "Config: $config\n";
	print "-" x 80 . "\n";
	print $console->get_config($config) . "\n";
}


my %stats_counter = $console->get_stats();
while (my ($stat, $value) = each %stats_counter) {
	print "$stat = $value\n";
}

if ($console->ping()) {
	print "I am alive!\n";
}
else {
	print "I am dead: " . $console->get_error() . "\n";
}

my $console2 = Varnish::Management->new("localhost", "9002");


if ($console2->ping()) {
	print "I am alive!\n";
}
else {
	print "I am dead: " . $console2->get_error() . "\n";
}

