package Varnish::Management;

use strict;
use IO::Socket::INET;
use Exporter;
use List::Util qw(first);

{
	my %hostname_of;
	my %port_of;
	my %error_of;
	my %socket_of;

	sub new {
		my ($class, $hostname, $port) = @_;

		my $new_object = bless \do{ my $anon_scalar; }, $class;

		$hostname_of{$new_object} = $hostname;
		$port_of{$new_object} = $port;
		$error_of{$new_object} = "";

		return $new_object;
	}

	sub _send_command {
		my ($self, $command) = @_;

		if (!$socket_of{$self} || !$socket_of{$self}->connected ) {
			my $socket = new IO::Socket::INET->new(
					PeerPort => $port_of{$self},
					Proto	 => 'tcp',
					PeerAddr => $hostname_of{$self}
					);
			return ("666", "Could not connect to node") if (!$socket);
			$socket_of{$self} = $socket;
		}
		my $socket = $socket_of{$self};
		
		print $socket "$command\n";
		my ($status_code, $response_size) = <$socket> =~ m/^(\d+) (\d+)/;
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

	sub send_command {
		my ($self, $command) = @_;
	
		my ($status_code, $response) = _send_command($self, $command);

		return no_error($self, $response) if $status_code eq "200";
		return set_error($self, $response);
	}

	sub get_parameters {
		my ($self) = @_;

		my %param;
		my $current_param;

		my ($status_code, $response) = _send_command($self, "param.show -l");
		return set_error($self, $response) if ($status_code ne "200");
		for my $line (split( '\n', $response)) {

			if ($line =~ /^(\w+)\s+(\w+) (.*)$/) {
				my %param_info = (
						value 	=> $2,
						unit	=> $3
						);

				$current_param = $1;
				$param{$1} = \%param_info;
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

		return no_error($self, $1) if ($response =~ /^(?:\w+)\s+(\w+)/);
		return set_error($self, $response);
	}

	sub set_parameter {
		my ($self, $parameter, $value) = @_;

		my ($status_code, $response) = _send_command($self, "param.set $parameter $value");

		return no_error($self) if ($status_code eq "200");
		return set_error($self, $response);
	}

	sub get_vcl_names {
		my ($self) = @_;

		my ($status_code, $response) = _send_command($self, "vcl.list");
		return set_error($self, $response) if ($status_code ne "200");

		my @vcl_infos = ($response =~ /^(\w+)\s+\d+\s+(\w+)$/gm);
		my $vcl_names_ref = [];
		my $active_vcl_name = "";
		while (my ($status, $name) = splice @vcl_infos, 0, 2) {
			next if ($status eq "discarded");

			if ($status eq "active") {
				$active_vcl_name = $name;
			}
			push @$vcl_names_ref, $name;
		}

		unshift @$vcl_names_ref, $active_vcl_name;
		return no_error($self, $vcl_names_ref) if ($status_code eq "200");
	}
	
	sub get_vcl {
		my ($self, $vcl_name) = @_;

		my ($status_code, $response) = _send_command($self, "vcl.show $vcl_name");

		return no_error($self, $response) if ($status_code eq "200");
		return set_error($self, $response);
	}

	sub set_vcl {
		my ($self, $vcl_name, $vcl) = @_;
		$vcl =~ s/"/\\"/g;
		$vcl =~ s/\r//g;
		$vcl =~ s/\n/\\n/g;

		my $need_restart = 0;
		my ($active_vcl_name, @vcl_names) = @{get_vcl_names($self)};
		my $editing_active_vcl = $vcl_name eq $active_vcl_name;

		# try to compile the new vcl
		my ($status_code, $response) = _send_command($self, "vcl.inline _new_vcl \"$vcl\"");
		if ($status_code ne "200") {
			_send_command($self, "vcl.discard _new_vcl");
			return set_error($self, $response);
		}

		if ($editing_active_vcl) {
			($status_code, $response) = _send_command($self, "vcl.use _new_vcl");
		}

		if (grep { $_ eq $vcl_name } @vcl_names) {
			($status_code, $response) = _send_command($self, "vcl.discard $vcl_name");
			if ($status_code ne "200") {
				_send_command($self, "vcl.use $vcl_name");
				_send_command($self, "vcl.discard _new_vcl");
				return set_error($self, $response);
			}
		}
		($status_code, $response) = _send_command($self, "vcl.inline $vcl_name \"$vcl\"");

		if ($editing_active_vcl) {
			($status_code, $response) = _send_command($self, "vcl.use $vcl_name");
		}
		_send_command($self, "vcl.discard _new_vcl");

		return no_error($self) if ($status_code eq "200");
		return set_error($self, $response);
	}

	sub discard_vcl {
		my ($self, $vcl_name) = @_;

		my ($status_code, $response) = _send_command($self, "vcl.discard $vcl_name");

		return no_error($self) if ($status_code eq "200");
		return set_error($self, $response);
	}

	sub make_vcl_active {
		my ($self, $vcl_name) = @_;

		my ($status_code, $response) = _send_command($self, "vcl.use $vcl_name");

		return no_error($self) if ($status_code eq "200");
		return set_error($self, $response);
	}

	sub get_stats {
		my ($self) = @_;

		my ($status_code, $response) = _send_command($self, "stats");

		my %stat_counter = map {
								/^\s*(\d+)\s+(.*?)$/;
								$2 => $1
							} split /\n/, $response;

		return no_error($self, \%stat_counter) if ($status_code eq "200");
		return set_error($self, $response);
	}

	sub ping {
		my ($self) = @_;

		my ($status_code, $response) = _send_command($self, "stats");

		return no_error($self) if ($status_code eq "200");
		return set_error($self, $response);
	}

	sub start {
		my ($self) = @_;

		my ($status_code, $response) = _send_command($self, "start");

		return no_error($self) if ($status_code eq "200");
		return set_error($self, $response);
	}

	sub stop {
		my ($self) = @_;

		my ($status_code, $response) = _send_command($self, "stop");

		return no_error($self) if ($status_code eq "200");
		return set_error($self, $response);
	}

	sub set_error {
		my ($self, $error) = @_;

		$error_of{$self} = $error;

		return;
	}

	sub get_error {
		my ($self) = @_;

		return $error_of{$self};
	}

	sub no_error {
		my ($self, $return_value) = @_;

		$error_of{$self} = "";

		return defined($return_value) ? $return_value : 1;
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
		return set_error($self, $response) if ($status_code ne "200");
		
		my %backend_health = ($response =~ /^Backend (\w+) is (\w+)$/gm);

		return no_error($self, \%backend_health);
	}
}

1;
