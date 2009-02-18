package Varnish::Node;

use strict;
use LWP::UserAgent;
use Varnish::Management;
use Varnish::Util;
use Varnish::DB;

{
	my %name_of;
	my %address_of;
	my %port_of;
	my %group_id_of;
	my %management_of;
	my %management_port_of;
	my %id_of;

	sub new {
		my ($class, $arg_ref) = @_;

		my $new_object = bless \do{ my $anon_scalar; }, $class;

		$id_of{$new_object} = $arg_ref->{'id'};
		$name_of{$new_object} = $arg_ref->{'name'};
		$address_of{$new_object} = $arg_ref->{'address'};
		$port_of{$new_object} = $arg_ref->{'port'};

		if ($arg_ref->{'group_id'}) {
			$group_id_of{$new_object} = $arg_ref->{'group_id'};
		}
		elsif ($arg_ref->{'group'}) {
			$group_id_of{$new_object} = Varnish::DB->get_group_id($arg_ref->{'group'});
		}
		else {
			$group_id_of{$new_object} = 0;
		}
		$management_port_of{$new_object} = $arg_ref->{'management_port'};
		$management_of{$new_object} = Varnish::Management->new($arg_ref->{'address'}, 
															   $arg_ref->{'management_port'});
		return $new_object;
	}

	sub DESTROY {
		my ($self) = @_;

		$management_of{$self}->close();
	}

	sub get_id {
		my ($self) = @_;

		return $id_of{$self};
	}

	sub get_name {
		my ($self) = @_;

		return $name_of{$self};
	}

	sub set_name {
		my ($self, $name) = @_;

		$name_of{$self} = $name;
	}

	sub get_address {
		my ($self) = @_;

		return $address_of{$self};
	}
	
	sub set_address {
		my ($self, $address) = @_;

		$address_of{$self} = $address;
	}

	sub get_port {
		my ($self) = @_;

		return $port_of{$self};
	}

	sub set_port {
		my ($self, $port) = @_;

		$port_of{$self} = $port;
	}

	sub get_group_id {
		my ($self) = @_;

		return $group_id_of{$self};
	}

	sub set_group_id {
		my ($self, $group_id) = @_;

		$group_id_of{$self} = $group_id;
	}

	sub get_management {
		my ($self) = @_;

		return $management_of{$self};
	}

	sub get_management_port {
		my ($self) = @_;

		return $management_port_of{$self};
	}

	sub set_management_port {
		my ($self, $management_port) = @_;

		$management_port_of{$self} = $management_port;
	}

	sub set_id {
		my ($self, $id) = @_;

		$id_of{$self} = $id;
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

	sub get_parameters {
		my ($self) = @_;

		return get_management($self)->get_parameters();
	}

	sub update_parameters {
		my ($self, $parameter_ref) = @_;
		
		my @parameters = keys %$parameter_ref;
		my $management = get_management($self);
		for my $parameter (@parameters) {
			$management->set_parameter($parameter, $parameter_ref->{$parameter}->{'value'});
#			$management->set_parameter($parameter, $parameter_ref->{$parameter});
		}
	}

	sub start {
		my ($self) = @_;

		my $management = get_management($self);
		if ($management->start()) {
			return no_error();
		}
		else {
			return set_error(get_error());
		}
	}

	sub stop {
		my ($self) = @_;

		my $management = get_management($self);
		if ($management->stop()) {
			return no_error();
		}
		else {
			return set_error(get_error());
		}
	}

	sub get_backend_health {
		my ($self) = @_;
		
		my $management = get_management($self);
		
		return $management->get_backend_health();
	}

	sub get_vcl_infos {
		my ($self) = @_;

		my $management = get_management($self);
		
		return $management->get_vcl_infos();
	}

	sub get_vcl {
		my ($self, $name) = @_;

		my $management = get_management($self);
		
		return $management->get_vcl($name);
	}

	sub save_vcl {
		my ($self, $name, $vcl) = @_;

		my $management = get_management($self);
		
		return $management->set_vcl($name, $vcl);
	}

	sub make_vcl_active {
		my ($self, $name) = @_;

		my $management = get_management($self);
		
		return $management->make_vcl_active($name);
	}

	sub discard_vcl {
		my ($self, $name) = @_;

		my $management = get_management($self);
		
		return $management->discard_vcl($name);
	}
}

1;
