package Varnish::NodeManager;
use strict;
use warnings;
use Varnish::Node;
use List::Util qw(first);

{
	my @groups = ();
	my @nodes = ();
	my %group_parameters = ();

	my $error = "";

	sub add_node {
		my ($self, $node) = @_;

		my $group = $node->get_group();
		if (! grep { $_->get_group eq $group } @nodes ) {
			$node->set_master(1);
			my %node_parameters = %{$node->get_management()->get_parameters()};
			while (my ($parameter, $value) = each %node_parameters) {
				$group_parameters{$group}->{$parameter} = $value;
			}
		}
		else {
# inherit the VCL and the parameters of the group
			my %group_parameters = %{$group_parameters{$group}};
			my $management = $node->get_management();
			while (my ($parameter, $value) = each %group_parameters) {
				$management->set_parameter($parameter, $value->{'value'});
			}

			my $vcl_names_ref = $management->get_vcl_names();
			my $active_vcl_name;
			my @vcl_names;
			if ($vcl_names_ref) {
				@vcl_names = @{$vcl_names_ref};
				$active_vcl_name = shift @vcl_names;
			}

			for my $vcl_name (@vcl_names) {
				if ($vcl_name ne $active_vcl_name) {
					$management->discard_vcl($vcl_name);
				}
			}
		
			my $discard_active_vcl = 1;
			my $group_master = first {
									$_->get_group() eq $group
									&& $_->is_master()
								} @nodes;
			my $master_management = $group_master->get_management();
			my $master_active_vcl_name;
			my @master_vcl_names;
			my $master_vcl_names_ref = $group_master->get_management()->get_vcl_names();
			if ($master_vcl_names_ref) {
				@master_vcl_names = @{$master_vcl_names_ref};
				$master_active_vcl_name = shift @master_vcl_names;
			}

			for my $vcl_name (@master_vcl_names) {
				my $vcl = $master_management->get_vcl($vcl_name); 
				$management->set_vcl($vcl_name, $vcl);

				if ($vcl_name eq $master_active_vcl_name) {
					$management->make_vcl_active($vcl_name);
				}
				if ($vcl_name eq $active_vcl_name) {
					$discard_active_vcl = 0;
				}
			}

			if ($discard_active_vcl) {
				$management->discard_vcl($active_vcl_name);
			}
		}

		push @nodes, $node;
	}

	sub remove_node {
		my ($self, $node) = @_;

		if ($node) {
			@nodes = grep { $_ != $node } @nodes;

			if ($node->is_master()) {
				my $new_master = first {
									$_->is_master
									&& $_->get_group() eq $node->get_group()
								 } @nodes;
				if ($new_master) {
					$new_master->set_master(1);
				}
			}
		}
	}

	sub get_node {
		my ($self, $node_id) = @_;
		
		my $node = first {
						$_->get_id() == $node_id
					} @nodes;

		return $node;
	}

	sub add_group {
		my ($self, $name) = @_;

		push @groups, $name;
	}

	sub remove_group {
		my ($self, $name) = @_;

		@groups = grep { $_ ne $name } @groups;
		my @nodes_to_remove = grep { $_->get_group() eq $name } @nodes;
		for my $node (@nodes_to_remove) {
			remove_node($self, $node);
		}
	}

	sub get_groups {

		return @groups;
	}

	sub get_nodes {

		return @nodes;
	}

	sub get_nodes_for_group {
		my ($self, $group) = @_;

		return grep { $_->get_group() eq $group } @nodes;
	}

	sub get_group_masters {
		my ($self) = @_;

		return grep { $_->is_master() } @nodes;
	}

	sub load {


	}

	sub save {
		my ($self) = @_;

	}

	sub quit {
		my ($self) = @_;

		for my $node (@nodes) {
			my $management = $node->get_management();
			if ($management) {
				$management->close();
			}
		}
		
		save($self);
	}

	sub set_error {
		my ($self, $new_error) = @_;

		$error = $new_error;

		return;
	}

	sub get_error {
		my ($self) = @_;

		return $error;
	}

	sub no_error {
		my ($self, $return_value) = @_;

		$error = "";

		return defined($return_value) ? $return_value : 1;
	}

	sub set_group_parameter {
		my ($self, $group, $parameter, $value) = @_;

		my $error;

		$group_parameters{$group}->{$parameter}->{'value'} = $value;
		my @nodes_in_group = grep { $_->get_group() eq $group } @nodes;
		for my $node (@nodes_in_group) {
			my $management = $node->get_management();
			if (!$management->set_parameter($parameter, $value)) {
				$error .= $management->get_error() . "\n";
			}
		}

		if ($error) {
			return set_error($self, $error);
		}
		else {
			return no_error();
		}
	}

	sub get_group_parameters {
		my ($self, $group) = @_;

		return $group_parameters{$group};
	}
}

1;
