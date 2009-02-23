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
use Varnish::DB;


# Configuration starts here
my %config = (
# 'address' is the IP to bind to. If not set, it listens on all.
#	address				=> localhost,

# 'port' is the port of the web server
	port				=> 8000,

# 'poll_intervall' is the polling interval for the statistics
	poll_interval		=> 5,

# 'restricted' gives a restricted version of the web GUI, disabling the user
# from changing any values
	restricted			=> 0,

# 'graph_width' and 'graph_height' are width and height for the graphs in 'View stats'
	graph_width			=> 250,
	graph_height		=> 125,
# 'large_graph_width' and 'large_graph_height' are width and height for the full size graph
# when clicking a stat graph in 'View stats'
	large_graph_width	=> 1000,
	large_graph_height	=> 500,

# 'log_filename' is the filename to log errors and information about actions done in the GUI
	log_filename		=> "varnish.log",

# 'db_filename' is the sqlite3 database created with the SQL outputed from create_db_data.pl
	db_filename			=> 'varnish.db',
);
# End of configuration

set_config(\%config);

# catch interupt to stop the daemon
$SIG{'INT'} = sub {
	print "Interrupt detected.\n";
};

# ignore the occational sigpipe
$SIG{'PIPE'} = sub { 
#	print "Pipe ignored\n";
};

log_info("Starting HTTP daemon");
my $daemon = HTTP::Daemon->new(	LocalPort => $config{'port'}, 
								LocalAddr => $config{'address'},
								ReuseAddr => 1 );

if (!$daemon) {
	log_error("Could not start HTTP daemon");
	die "Could not start web server";
}
log_info("HTTP daemon started with URL " . $daemon->url);
print "Web server started with URL: " . $daemon->url, "\n";
my $data_collector_handle = threads->create('data_collector_thread');
while (my $connection = $daemon->accept) {
	REQUEST:
	while (my $request = $connection->get_request) {
		$connection->force_last_request;
#		print "Request for: " . $request->uri . "\n";
		if ($request->uri =~ m{/(.*?\.png)} ||
			$request->uri =~ m{/(.*?\.ico)}) {
			my $filename = $1;
			
			$connection->send_file_response($filename);
			next REQUEST;
		}
		elsif ($request->uri =~ m{/(.*?\.css)}) {
			my $filename = $1;
			
			$connection->send_basic_header();
			print $connection "Content-Type: text/css";
			$connection->send_crlf();
			$connection->send_crlf();
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
log_info("Shutting down web server");
$daemon->close();
Varnish::DB->finish();
log_info("Stopping data collector thread");
$data_collector_handle->join();

sub data_collector_thread {
	my $url = $daemon->url . "collect_data";
	my $interval = $config{'poll_interval'};
	
	log_info("Data collector thread started. Polling URL $url at $interval seconds interval");
	sleep 1; # wait for the server to come up
	while (1) {
		my $user_agent = LWP::UserAgent->new;
		$user_agent->timeout(10);
		my $response = $user_agent->get($url);
			
		last if ($response->code eq "500");
		sleep($interval);
	}
	print "Data collector thread stopped.\n";
}
