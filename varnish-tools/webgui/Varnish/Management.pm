package Varnish::Management;

use strict;
use IO::Socket::INET;
use IO::Select;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Exporter;
use List::Util qw(first);
use Varnish::Util qw(set_error get_error no_error);
use Digest::SHA qw(sha256_hex);

{
	my %hostname_of;
	my %port_of;
	my %socket_of;
	my %secret_of;

	sub new {
		my ($class, $hostname, $port, $secret) = @_;

		my $new_object = bless \do{ my $anon_scalar; }, $class;

		$hostname_of{$new_object} = $hostname;
		$port_of{$new_object} = $port;
		$secret_of{$new_object} = $secret;

		return $new_object;
	}

	sub _read_cli_response {
		my ($socket) = @_;
		
		my $status_line = <$socket>;
		return (undef, undef) if !defined($status_line);
		my ($status_code, $response_size) = $status_line =~ m/^(\d+) (\d+)/;

		my $response;
		my $remaining_bytes = $response_size;
		while ($remaining_bytes > 0 ) {
			my $data;
			my $read = read $socket, $data, $remaining_bytes;
			$response .= $data;
			$remaining_bytes -= $read;
		}
		my $eat_newline = <$socket>;

		return ($status_code, $response);
	}

	sub _send_command {
		my ($self, $command) = @_;

		if (!$socket_of{$self} || !$socket_of{$self}->connected ) {
			my $socket = new IO::Socket::INET->new(
					PeerPort => $port_of{$self},
					Proto	 => 'tcp',
					PeerAddr => $hostname_of{$self},
					Blocking => 0,

					);
			return ("666", "Could not connect to node") if (!$socket);

			my $select = IO::Select->new();
			$select->add($socket);
			my $status_code;
			my $response;
			# wait 100ms, tops, before assuming we don't get a banner
			if ($select->can_read(0.1)) {
				($status_code, $response) = _read_cli_response($socket);
			}
			my $flags = fcntl($socket, F_GETFL, 0);
			$flags = fcntl($socket, F_SETFL, $flags & ~O_NONBLOCK);
					
			if ($status_code && $status_code eq "107") {
				my ($challenge) = ($response =~ /^(.*)$/m);
				my $challenge_response_text =
					"$challenge\n" . $secret_of{$self} . "\n$challenge\n";	

				print $socket "auth " . sha256_hex($challenge_response_text) . "\n";
				my ($status_code, $response) = _read_cli_response($socket);
				if ($status_code ne "200") {
					close($socket);
					return ("666", "Management port authentication failed.");
				}
			}

			$socket_of{$self} = $socket;
		}
		my $socket = $socket_of{$self};
		print $socket "$command\n";
		return _read_cli_response($socket);
	}

	sub send_command {
		my ($self, $command) = @_;
	
		my ($status_code, $response) = _send_command($self, $command);

		return no_error($response) if $status_code eq "200";
		return set_error($response);
	}

	sub get_parameters {
		my ($self) = @_;

		my %param;
		my $current_param;

		my ($status_code, $response) = _send_command($self, "param.show -l");
		return set_error($response) if ($status_code ne "200");
		for my $line (split( '\n', $response)) {

			if ($line =~ /^(\w+)\s+(.*?)(?: \[(.*)\])?$/) {
				my $value = $2;
				my $unit = $3;
				$current_param = $1;

				if ($current_param eq "user" || $current_param eq "group" 
					|| $current_param eq "waiter") {
					($value) = split(/ /, $value);
				}
				my %param_info = (
						value 	=> $value,
						unit	=> $unit
						);
				$param{$current_param} = \%param_info;
			}
			elsif ($line =~ /^\s+(.+)$/) {
# The first comment line contains no . and describes the default value.
				if (!$param{$current_param}->{'description'}) {
					$param{$current_param}->{'description'} = "$1. ";
				}
				else  {
					$param{$current_param}->{'description'} .= "$1 ";
				}
			}
		}

		return \%param;
	}

	sub get_parameter($) {
		my ($self, $parameter) = @_;

		my ($status_code, $response) = _send_command($self, "param.show $parameter");

		return no_error($1) if ($response =~ /^(?:\w+)\s+(\w+)/);
		return set_error($response);
	}

	sub set_parameter {
		my ($self, $parameter, $value) = @_;

		my ($status_code, $response) = _send_command($self, "param.set $parameter $value");

		return no_error($self) if ($status_code eq "200");
		return set_error($response);
	}

	sub get_vcl_infos {
		my ($self) = @_;

		my ($status_code, $response) = _send_command($self, "vcl.list");
		return set_error($response) if ($status_code ne "200");

		my @vcl_infos = ($response =~ /^(\w+)\s+(?:\d+|N\/A)\s+(\w+)$/gm);
		my $vcl_names_ref = [];
		while (my ($status, $name) = splice @vcl_infos, 0, 2) {
			next if ($status eq "discarded");
			
			push @$vcl_names_ref, {
				name	=>	$name,
				active	=>	$status eq "active",
			};
		}

		return no_error($vcl_names_ref) if ($status_code eq "200");
	}
	
	sub get_vcl {
		my ($self, $vcl_name) = @_;

		my ($status_code, $response) = _send_command($self, "vcl.show $vcl_name");

		return no_error($response) if ($status_code eq "200");
		return set_error($response);
	}

	sub set_vcl {
		my ($self, $vcl_name, $vcl) = @_;
		$vcl =~ s/\\/\\\\/g;
		$vcl =~ s/"/\\"/g;
		$vcl =~ s/\r//g;
		$vcl =~ s/\n/\\n/g;

		my $need_restart = 0;
		my $vcl_info = first { $_->{'name'} eq $vcl_name } @{get_vcl_infos($self)};

		# try to compile the new vcl
		my ($status_code, $response) = _send_command($self, "vcl.inline _new_vcl \"$vcl\"");
		if ($status_code ne "200") {
			_send_command($self, "vcl.discard _new_vcl");
			return set_error($response);
		}

		if ($vcl_info && $vcl_info->{'active'}) {
			($status_code, $response) = _send_command($self, "vcl.use _new_vcl");
		}

		if ($vcl_info) {
			($status_code, $response) = _send_command($self, "vcl.discard $vcl_name");
			if ($status_code ne "200") {
				_send_command($self, "vcl.use $vcl_name");
				_send_command($self, "vcl.discard _new_vcl");
				return set_error($response);
			}
		}
		($status_code, $response) = _send_command($self, "vcl.inline $vcl_name \"$vcl\"");

		if ($vcl_info && $vcl_info->{'active'}) {
			($status_code, $response) = _send_command($self, "vcl.use $vcl_name");
		}
		_send_command($self, "vcl.discard _new_vcl");

		return no_error($self) if ($status_code eq "200");
		return set_error($response);
	}

	sub discard_vcl {
		my ($self, $vcl_name) = @_;

		my ($status_code, $response) = _send_command($self, "vcl.discard $vcl_name");

		return no_error($self) if ($status_code eq "200");
		return set_error($response);
	}

	sub make_vcl_active {
		my ($self, $vcl_name) = @_;

		my ($status_code, $response) = _send_command($self, "vcl.use $vcl_name");

		return no_error($self) if ($status_code eq "200");
		return set_error($response);
	}

	sub get_stats {
		my ($self) = @_;

		my ($status_code, $response) = _send_command($self, "stats");

		my %stat_counter = map {
								/^\s*(\d+)\s+(.*?)$/;
								$2 => $1
							} split /\n/, $response;
		return no_error(\%stat_counter) if ($status_code eq "200");
		return set_error($response);
	}

	sub ping {
		my ($self) = @_;

		my ($status_code, $response) = _send_command($self, "ping");
		
		return no_error($self) if ($status_code eq "200");
		return set_error($response);
	}

	sub start {
		my ($self) = @_;

		my ($status_code, $response) = _send_command($self, "start");

		return no_error($self) if ($status_code eq "200");
		return set_error($response);
	}

	sub stop {
		my ($self) = @_;

		my ($status_code, $response) = _send_command($self, "stop");

		return no_error($self) if ($status_code eq "200");
		return set_error($response);
	}

	sub close {
		my ($self) = @_;

		if ($socket_of{$self} && $socket_of{$self}->connected) {
			$socket_of{$self}->close();
		}
	}

	sub get_backend_health {
		my ($self) = @_;

		my ($status_code, $response) = _send_command($self, "debug.health");
		return set_error($response) if ($status_code ne "200");
		
		my %backend_health = ($response =~ /^Backend (\w+) is (\w+)$/gm);

		return no_error(\%backend_health);
	}
}

1;
