package Varnish::Node;

use strict;
use LWP::UserAgent;
use Varnish::Management;

{
	my %name_of;
	my %address_of;
	my %port_of;
	my %group_of;
	my %management_of;
	my %management_port_of;
	my %is_master_of;
	my %node_id_of;

	my $next_node_id = 1;

	sub new {
		my ($class, $arg_ref) = @_;

		my $new_object = bless \do{ my $anon_scalar; }, $class;

		$name_of{$new_object} = $arg_ref->{'name'};
		$address_of{$new_object} = $arg_ref->{'address'};
		$port_of{$new_object} = $arg_ref->{'port'};
		$group_of{$new_object} = $arg_ref->{'group'};
		$management_port_of{$new_object} = $arg_ref->{'management_port'};
		$management_of{$new_object} = Varnish::Management->new($arg_ref->{'address'}, 
															   $arg_ref->{'management_port'});
		$is_master_of{$new_object} = 0;
		$node_id_of{$new_object} = $next_node_id++;

		return $new_object;
	}

	sub get_id {
		my ($self) = @_;

		return $node_id_of{$self};
	}

	sub get_name {
		my ($self) = @_;

		return $name_of{$self};
	}

	sub get_address {
		my ($self) = @_;

		return $address_of{$self};
	}

	sub get_port {
		my ($self) = @_;

		return $port_of{$self};
	}

	sub get_group {
		my ($self) = @_;

		return $group_of{$self};
	}

	sub get_management {
		my ($self) = @_;

		return $management_of{$self};
	}

	sub get_management_port {
		my ($self) = @_;

		return $management_port_of{$self};
	}

	sub is_master {
		my ($self) = @_;

		return $is_master_of{$self};
	}

	sub set_master {
		my ($self, $master) = @_;

		$is_master_of{$self} = $master;
	}

	sub is_running_ok {
		my ($self) = @_;

		my $user_agent = LWP::UserAgent->new;
		$user_agent->timeout(1);

		my $url = 'http://' . get_address($self) . ':' . get_port($self);
		my $response = $user_agent->head($url);
		return $response->is_success;
	}

	sub is_running {
		my ($self) = @_;

		my $user_agent = LWP::UserAgent->new;
		$user_agent->timeout(1);

		my $url = 'http://' . get_address($self) . ':' . get_port($self);
		my $response = $user_agent->head($url);
		return $response->code != 500;
	}


	sub is_management_running {
		my ($self) = @_;

		my $management = get_management($self);
		if ($management) {
			my $ping = $management->ping();
			return defined($ping) && $ping;
		}
		else {
			return 0;
		}
	}
}

1;
