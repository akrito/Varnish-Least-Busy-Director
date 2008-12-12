#!/usr/bin/perl
use threads;
use strict;
use warnings;
use HTTP::Daemon;
use HTTP::Status;
use HTTP::Request;
use LWP::UserAgent;
use Varnish::Util;
use Varnish::RequestHandler;
use Varnish::NodeManager;
use Varnish::Node;
use Varnish::Statistics;


# Configuration starts here
my %config = (
# 'address' is the IP to bind to. If not set, it listens on all.
#	address				=> localhost,

# 'port' is the port of the web server
	port				=> 8000,

# 'poll_intervall' is the polling interval for the statistics
	poll_interval		=> 5,
);

# create some default groups 
my @groups = qw(default images);

# create some default nodes 
my @node_params = (
	{
		name 			=> 'varnish-1',
		address			=> 'localhost',
		port			=> '80',
		group			=> 'default',
		management_port	=> 9001,
	},
	{
		name 			=> 'varnish-2',
		address			=> 'localhost',
		port			=> '8181',
		group			=> 'default',
		management_port	=> 9002,
	},
	{
		name 			=> 'varnish-1',
		address			=> 'localhost',
		port			=> '8888',
		group			=> 'images',
		management_port	=> 9003,
	},
);

# End of configuration

set_config(\%config);

for my $group (@groups) {
	Varnish::NodeManager->add_group($group);
}

for my $node_param_ref (@node_params) {
	my $group_exists =	grep {
							$_ eq $node_param_ref->{'group'}
						} @groups;
	if ($group_exists) {
		my $node = Varnish::Node->new($node_param_ref);
		Varnish::NodeManager->add_node($node);
	}
	else {
		print "Node " . $node_param_ref->{'name'} . " has an invalid group "
				. $node_param_ref->{'group'} . ". Skipping.";
	}
}

# catch interupt to stop the daemon
$SIG{'INT'} = sub {
	print "Interrupt detected.\n";
};

# ignore the occational sigpipe
$SIG{'PIPE'} = sub { 
#	print "Pipe ignored\n";
};

my $daemon = HTTP::Daemon->new(	LocalPort => $config{'port'}, 
								LocalAddr => $config{'address'},
								ReuseAddr => 1 ) || die "Could not start web server";
print "Web server started with URL: " . $daemon->url, "\n";
my $data_collector_handle = threads->create('data_collector_thread');
while (my $connection = $daemon->accept) {
	REQUEST:
	while (my $request = $connection->get_request) {
		$connection->force_last_request;
		if ($request->uri =~ m{/(.*?\.png)} ||
			$request->uri =~ m{/(.*?\.css)} ||
			$request->uri =~ m{/(.*?\.ico)}) {
			my $filename = $1;
			
			$connection->send_file($filename);
			next REQUEST;
		}
		
		my $request_handler = Varnish::RequestHandler->new(\$request, $connection);
		$request_handler->process();

		my $response = HTTP::Response->new(200);
		$response->header( $request_handler->get_response_header() );
		$response->content( $request_handler->get_response_content() );
		$connection->send_response($response);
	}
	$connection->close();
	undef($connection);
}
print "Shutting down!\n";
$daemon->close();
Varnish::NodeManager->quit();
print "Stopping data collector thread\n";
$data_collector_handle->join();

sub data_collector_thread {
	my $url = $daemon->url . "collect_data";
	my $interval = $config{'poll_interval'};
	print "Data collector thread started. Polling URL $url at $interval seconds interval\n";

	sleep 1; # wait for the server to come up
	while (1) {
		my $user_agent = LWP::UserAgent->new;
		$user_agent->timeout(6);
		my $response = $user_agent->get($url);
			
		last if ($response->code eq "500");
		sleep $interval;
	}
	print "Data collector thread stopped.\n";
}
