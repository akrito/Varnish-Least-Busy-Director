package Varnish::NodeManager;
use strict;
use warnings;
use Varnish::Node;
use Varnish::Group;
use Varnish::Util qw(set_error no_error get_error);
use List::Util qw(first);

{
	my $error = "";

	sub _clone_unit {
		my ($master, $slave) = @_;

		my $parameter_ref = $master->get_parameters();
		$slave->update_parameters($parameter_ref);
	
		my $master_vcl_infos_ref = $master->get_vcl_infos();
		for my $vcl_info (@$master_vcl_infos_ref) {
			my $name = $vcl_info->{'name'};
			$vcl_info->{'vcl'} = $master->get_vcl($name);
		}

		my $slave_active_vcl = "";
		my $discard_slave_active_vcl = 0;
		my $vcl_infos_ref = $slave->get_vcl_infos();
		for my $vcl_info (@$vcl_infos_ref) {
			my $name = $vcl_info->{'name'};
			if ($vcl_info->{'active'}) {
				$slave_active_vcl = $name;
				$discard_slave_active_vcl = 1;
			}
			else {
				$slave->discard_vcl($name);
			}
		}

		for my $vcl_info (@$master_vcl_infos_ref) {
			my $name = $vcl_info->{'name'};
			my $vcl = $vcl_info->{'vcl'};
			$slave->save_vcl($name, $vcl);
			if ($vcl_info->{'active'}) {
				$slave->make_vcl_active($name);
			}
			if ($slave_active_vcl eq $name) {
				$discard_slave_active_vcl = 0;
			}
		}
		if ($discard_slave_active_vcl) {
			$slave->discard_vcl($slave_active_vcl);
		}	
	}
	
	sub add_node {
		my ($self, $node, $inheritance) = @_;

		$inheritance ||= 0;
		my $management = $node->get_management();
		if (!$management->ping()) {
			return set_error("Could not connect to management port: "
									. get_error());
		}
		Varnish::DB->add_node($node);

		my $group_id = $node->get_group_id();
		if ($group_id > 0 && $inheritance) {
			my $group = get_group($self, $group_id);
			if ($inheritance == 1) {
				_clone_unit($node, $group);
			}
			elsif ($inheritance == 2) {
				_clone_unit($group, $node);
			}
		}

		return no_error();
	}

	sub remove_node {
		my ($self, $node) = @_;

		Varnish::DB->remove_node($node);
	}

	sub get_node {
		my ($self, $node_id) = @_;
		
		my ($node) = @{Varnish::DB->get_nodes({id => $node_id})};

		return $node;
	}

	sub add_group {
		my ($self, $group) = @_;

		Varnish::DB->add_group($group);
	}

	sub remove_group {
		my ($self, $group) = @_;

		Varnish::DB->remove_group($group);
	}

	sub get_group {
		my ($self, $group_id) = @_;
		
		my ($group) = @{Varnish::DB->get_groups({id => $group_id})};

		return $group;
	}


	sub get_groups {

		return Varnish::DB->get_groups();
	}

	sub get_nodes {
		my ($self, $group) = @_;
		
		if (defined($group)) {
			return Varnish::DB->get_nodes({group_id => $group->get_id()});
		}
		else {
			return Varnish::DB->get_nodes();
		}
	}

	sub get_group_name {
		my ($self, $group_id) = @_;
	
		if ($group_id > 0) {
			my $group = get_group($self, $group_id);
			if ($group) {
				return $group->get_name();
			}
		}
		return '';
	}

	sub update_node {
		my ($self, $node, $inheritance) = @_;

		$inheritance ||= 0;
		my $current = get_node($self, $node->get_id());
		if ($current->get_group_id() != $node->get_group_id()
			&& $node->get_group_id() > 0
			&& $inheritance) {
			my $group = get_group($self, $node->get_group_id());

			if ($inheritance == 1) {
				_clone_unit($node, $group);
			}
			elsif ($inheritance == 2) {
				_clone_unit($group, $node);
			}
		}

		Varnish::DB->update_node($node);
	}

	sub update_group {
		my ($self, $group) = @_;

		Varnish::DB->update_group($group);
	}

}

1;
