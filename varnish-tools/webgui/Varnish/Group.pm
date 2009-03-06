package Varnish::Group;

use strict;

use Varnish::DB;
use Varnish::Util;

{
	my %id_of;
	my %name_of;
	my %active_vcl_of;

	my $parameter_info_ref;
	
	sub new {
		my ($class, $arg_ref) = @_;

		my $new_object = bless \do{ my $anon_scalar; }, $class;

		$id_of{$new_object} = $arg_ref->{'id'};
		$name_of{$new_object} = $arg_ref->{'name'};
		$active_vcl_of{$new_object} = $arg_ref->{'active_vcl'};

		return $new_object;
	}

	sub DESTROY {
		my ($self) = @_;

		delete $id_of{$self};
		delete $name_of{$self};
		delete $active_vcl_of{$self};
	}

	sub get_id {
		my ($self) = @_;

		return $id_of{$self};
	}

	sub get_name {
		my ($self) = @_;

		return $name_of{$self};
	}

	sub get_active_vcl {
		my ($self) = @_;

		return $active_vcl_of{$self};
	}

	sub get_parameters {
		my ($self) = @_;

		if (!$parameter_info_ref) {
			$parameter_info_ref = Varnish::DB->get_parameter_info();
		}
		my $parameter_ref = Varnish::DB->get_group_parameters($self);
		while (my ($parameter, $value) = each(%$parameter_ref)) {
			$parameter_ref->{$parameter} = {
				value		=> $value,
				unit		=> $parameter_info_ref->{$parameter}->{'unit'},
				description	=> $parameter_info_ref->{$parameter}->{'description'},
			};
		}
		
		return $parameter_ref;
	}

	sub update_parameters {
		my ($self, $parameter_ref) = @_;
		
		Varnish::DB->update_parameters($id_of{$self}, $parameter_ref);
	
		my $nodes_ref = Varnish::NodeManager->get_nodes($self);
		for my $node (@$nodes_ref) {
			$node->update_parameters($parameter_ref);
		}
	}

	sub set_id {
		my ($self, $id) = @_;

		$id_of{$self} = $id;
	}

	sub set_name {
		my ($self, $name) = @_;

		$name_of{$self} = $name;
	}

	sub get_vcl_infos {
		my ($self) = @_;
		
		return Varnish::DB->get_vcl_infos($id_of{$self});
	}

	sub get_vcl {
		my ($self, $name) = @_;

		return Varnish::DB->get_vcl($id_of{$self}, $name);
	}

	sub save_vcl {
		my ($self, $name, $vcl) = @_;
	
		my $vcl_error;
		my $error = "";
		my $nodes_ref = Varnish::NodeManager->get_nodes($self);
		for my $node (@$nodes_ref) {
			my $management = $node->get_management();
			if ($management) {
				if (!$management->set_vcl($name, $vcl)) {
					$vcl_error ||= get_error();
				}
			}
			else {
				$error .= "Could not get the management console for " . $node->get_name() . "\n"; 
			}
		}
		if ($vcl_error) {
			$error .= "VCL compilation errors:\n$vcl_error\n";
		}
		else {
			if (Varnish::DB->update_vcl($id_of{$self}, $name, $vcl) == 0 ) {
				Varnish::DB->add_vcl($id_of{$self}, $name, $vcl);
			}
		}

		if ($error) {
			return set_error($error);
		}
		else {
			return no_error();
		}
	}

	sub make_vcl_active {
		my ($self, $name) = @_;
	
		my $error = "";
		my $nodes_ref = Varnish::NodeManager->get_nodes($self);
		for my $node (@$nodes_ref) {
			my $management = $node->get_management();
			if ($management) {
				if (!$management->make_vcl_active($name)) {
					$error .= get_error();
				}
			}
			else {
				$error .= "Could not get the management console for " . $node->get_name() . "\n"; 
			}
		}

		$active_vcl_of{$self} = $name;
		if (Varnish::DB->update_group($self) == 0 ) {
			$error .= "$name is not a valid VCL\n";
		}

		if ($error) {
			return set_error($error);
		}
		else {
			return no_error();
		}
	}

	sub discard_vcl {
		my ($self, $name) = @_;
	
		my $error = "";
		my $nodes_ref = Varnish::NodeManager->get_nodes($self);
		for my $node (@$nodes_ref) {
			my $management = $node->get_management();
			if ($management) {
				if (!$management->discard_vcl($name)) {
					$error .= get_error();
				}
			}
			else {
				$error .= "Could not get the management console for " . $node->get_name() . "\n"; 
			}
		}
		if (Varnish::DB->discard_vcl($id_of{$self}, $name) == 0 ) {
			$error .= "$name is not a valid VCL\n";
		}

		if ($error) {
			return set_error($error);
		}
		else {
			return no_error();
		}
	}

	sub start {
		my ($self) = @_;

		my $error = "";
		my $nodes_ref = Varnish::NodeManager->get_nodes($self);
		for my $node (@$nodes_ref) {
			if (!$node->is_running()) {
				if (!$node->start()) {
					$error .= get_error();
				}
			}
		}
		
		if ($error) {
			return set_error($error);
		}
		else {
			return no_error();
		}
	}

	sub stop {
		my ($self) = @_;

		my $error = "";
		my $nodes_ref = Varnish::NodeManager->get_nodes($self);
		for my $node (@$nodes_ref) {
			if ($node->is_running()) {
				if (!$node->stop()) {
					$error .= get_error();
				}
			}
		}
		
		if ($error) {
			return set_error($error);
		}
		else {
			return no_error();
		}
	}

}

1;
