package Varnish::DB;

use strict;
use warnings;

use DBI;
use Varnish::Util;
use Varnish::Node;
use Varnish::Group;
use Varnish::DB_Data;

{
	my $dbh;
	my $stat_type_id_from_name_ref;
	my %stat_field_exist;
	my %parameter_field;
	
	sub handle_error {
		my ($error, $handler) = @_;

		$dbh->disconnect();
		$dbh =  DBI->connect("dbi:SQLite:dbname=test.db", '', '', 
			{ AutoCommit => 0, PrintError => 1, HandleError => \&handle_error } );
		sleep(1);
	}

	sub init {
		my ($self, $db_filename, $username, $password) = @_;

		$dbh =  DBI->connect("dbi:SQLite:dbname=$db_filename", '', '', 
			{ AutoCommit => 0, PrintError => 1});
		
		%parameter_field = %{Varnish::DB_Data::get_parameter_field()};
		%stat_field_exist = %{Varnish::DB_Data::get_stat_field_exist()};
	}


	sub add_stat {
		my ($self, $node, $stat_ref, $timestamp) = @_;

		$timestamp ||= time();

		my @field_values; 
		my $fields = "time, node_id, has_data";
		my $values = "?, ?, ?";
		my $has_data;
		if ($stat_ref) {
			$has_data = 1;
			my @stat_fields = keys %{$stat_ref};
			for my $stat_field (@stat_fields) {
				my $db_field = get_db_friendly_name($stat_field);
				if ($stat_field_exist{$db_field}) {
					$fields .= ", $db_field";
					$values .= ", ?";
					my $value = $stat_ref->{$stat_field};
					push @field_values, $value;
				}
				else {
					print STDERR "Field $db_field does not exist in the stat table. Please update schema by running create_db_data.pl\n";
				}
			}
		}
		else {
			$has_data = 0;
		}
		my $sql = "INSERT INTO stat($fields) VALUES($values)";
		my $sth = $dbh->prepare($sql);
		$sth->execute($timestamp, $node->get_id(), $has_data, @field_values);
		$sth->finish();
		$dbh->commit();
	}

	sub get_stat_data {
		my ($self, $unit, $after_timestamp, $stat_fields_ref) = @_;

		if (!defined($stat_fields_ref)) {
			my @stat_fields = keys(%stat_field_exist);

			$stat_fields_ref = \@stat_fields;
		}

		my $sql;
		if (ref($unit) eq "Varnish::Node") {
			$sql = "SELECT time, has_data";
			for my $stat_field (@$stat_fields_ref) {
				$sql .=", $stat_field";
			}
			$sql .= " FROM stat WHERE node_id = ? AND time > ? ORDER BY time ASC";
		}
		else {
			$sql = "SELECT time, SUM(has_data) as has_data";
			for my $stat_field (@$stat_fields_ref) {
				$sql .=", SUM($stat_field) AS $stat_field";
			}
			$sql .= " FROM stat WHERE node_id IN (SELECT id FROM node WHERE group_id = ?) AND time >= ? GROUP BY time ORDER BY time ASC";
		}

		return $dbh->selectall_arrayref($sql, {Slice => {}}, $unit->get_id(), $after_timestamp);
	}

	sub add_node {
		my ($self, $node) = @_;

		my $fields = "name, address, port, group_id, management_port";
		my $sql = "INSERT INTO node($fields) VALUES(?, ?, ?, ?, ?)";
		$dbh->do($sql, undef,
			$node->get_name(),
			$node->get_address(),
			$node->get_port(),
			$node->get_group_id(),
			$node->get_management_port());
		$dbh->commit();
		
		$node->set_id($dbh->func('last_insert_rowid'));
	}

	sub update_node {
		my ($self, $node) = @_;
	
		my $sql = 
			"UPDATE node SET name = ?, address = ?, port = ?, group_id = ?, "
			. "management_port = ? where id = ?";
		$dbh->do($sql, undef, $node->get_name, $node->get_address(), $node->get_port(),
			$node->get_group_id(), $node->get_management_port(),
			$node->get_id());
		$dbh->commit();
	}

	sub remove_node {
		my ($self, $node, $commit) = @_;
		
		$commit = 1 if (!defined($commit));

		my $sql = "DELETE FROM node WHERE id = ?";
		my $sth = $dbh->prepare($sql);
		$sth->execute($node->get_id());

		$sql = "DELETE FROM stat WHERE node_id = ?";
		$sth = $dbh->prepare($sql);
		$sth->execute($node->get_id());
	
		if ($commit) {
			$dbh->commit();
		}
	}

	sub add_group {
		my ($self, $group) = @_;

		my $sql = "INSERT INTO node_group(name) VALUES(?)";
		$dbh->do($sql, undef, $group->get_name());
		my $id = $dbh->func('last_insert_rowid');
		$group->set_id($id);

		$sql = "INSERT INTO parameters(group_id) VALUES(?)";
		$dbh->do($sql, undef, $id);
		update_parameters($self, $id, \%parameter_field);
		
		$dbh->commit();
	}

	sub update_group {
		my ($self, $group, $active_vcl) = @_;

		my $sql = "UPDATE node_group SET name = ?, active_vcl = ? WHERE id = ?";
		$dbh->do($sql, undef, $group->get_name(), $group->get_active_vcl(), $group->get_id());
		
		$dbh->commit();
	}

	sub remove_group {
		my ($self, $group) = @_;

		my $sql = "DELETE FROM node_group WHERE id = ?";
		my $sth = $dbh->prepare($sql);
		$sth->execute($group->get_id());

		$sql = "DELETE FROM parameters WHERE group_id = ?";
		$sth = $dbh->prepare($sql);
		$sth->execute($group->get_id());

		# sqlite doesn't support cascading delete, so we must do it
		$sql = "SELECT id FROM node WHERE group_id = ?";
		my $nodes_ref = get_nodes($self, { group_id => $group->get_id()});
		for my $node (@$nodes_ref) {
			remove_node($self, $node, 1);
		}

		$dbh->commit();
	}

	sub _create_criteria_sql {
		my ($criteria_ref) = @_;

		my @values;
		my $sql = "";
		if ($criteria_ref) {
			my @criterias = keys %$criteria_ref;
			for my $criteria (@criterias) {
				if ($sql eq "") {
					$sql = " WHERE";
				}
				else {
					$sql .= " AND";
				}
				my $value = $criteria_ref->{$criteria};
				$sql .= " $criteria = ?";
				push @values, $value;
			}
		}

		return ($sql, @values);
	}

	sub get_groups {
		my ($self, $criteria_ref) = @_;

		my @values;
		my $sql = "SELECT * FROM node_group"; 
		if ($criteria_ref) {
			my $criteria_sql;
			($criteria_sql, @values) = _create_criteria_sql($criteria_ref);
			$sql .= $criteria_sql;
		}
		my $group_rows_ref = $dbh->selectall_arrayref($sql, {Slice => {}}, @values);
		my @groups = map { Varnish::Group->new($_) } @$group_rows_ref;

		return \@groups;
	}

	sub get_nodes {
		my ($self, $criteria_ref) = @_;
		my @values;
		my $sql = "SELECT * FROM node"; 
		if ($criteria_ref) {
			my $criteria_sql;
			($criteria_sql, @values) = _create_criteria_sql($criteria_ref);
			$sql .= $criteria_sql;
		}

		my $node_rows_ref = $dbh->selectall_arrayref($sql, {Slice => {}}, @values);
		my @nodes = map { Varnish::Node->new($_) } @$node_rows_ref;

		return \@nodes;
	}


	sub _clean_up_parameters {
		my ($parameter_ref) = @_;

		# rename 'child_user' and 'child_group' to the proper 'user' and 'group' names
		$parameter_ref->{'user'} = $parameter_ref->{'child_user'};
		delete $parameter_ref->{'child_user'};
		$parameter_ref->{'group'} = $parameter_ref->{'child_group'};
		delete $parameter_ref->{'child_group'};
		delete $parameter_ref->{'id'};
		delete $parameter_ref->{'group_id'};
		delete $parameter_ref->{'node_id'};

		return $parameter_ref;
	}


	sub get_group_parameters {
		my ($self, $group) = @_;

		my $sql = "SELECT * FROM parameters WHERE group_id = ?";
		my $parameters_ref = $dbh->selectrow_hashref($sql, undef, $group->get_id());

		return _clean_up_parameters($parameters_ref);
	}


	sub get_node_parameters {
		my ($self, $node) = @_;

		my $sql = "SELECT * FROM parameters WHERE node_id = ?";
		my $parameters_ref = $dbh->selectrow_hashref($sql, undef, $node->get_id());

		# rename 'child_user' and 'child_group' to the proper 'user' and 'group' names
		$parameters_ref->{'user'} = $parameters_ref->{'child_user'};
		delete $parameters_ref->{'child_user'};
		$parameters_ref->{'group'} = $parameters_ref->{'child_group'};
		delete $parameters_ref->{'child_group'};
		delete $parameters_ref->{'id'};
		delete $parameters_ref->{'group_id'};
		delete $parameters_ref->{'node_id'};

		return _clean_up_parameters($parameters_ref);
	}

	sub update_parameters {
		my ($self, $group_id, $parameter_ref) = @_;

		my @parameters = keys %{$parameter_ref};
		my @values;
		my $first = 1;
		my $sql = "UPDATE parameters SET";
		for my $parameter (@parameters) {
			if (!$first) {
				$sql .= ", ";
			}
			else {
				$first = 0;
			}
			if ($parameter eq 'user' || $parameter eq 'group') {
				$sql .= " child_$parameter = ?";
			}
			elsif ($parameter_field{$parameter}) {
				$sql .= " $parameter = ?";
			}
			else {
				print STDERR "Field $parameter does not exist in the stat table. Please update schema\n";
				next;
			}
			push @values, $parameter_ref->{$parameter}->{'value'};
		}
		$sql .= " WHERE id = ?";
		$dbh->do($sql, undef, @values, $group_id);
	}

	sub get_parameter_info {
		my ($self) = @_;

		return $dbh->selectall_hashref("SELECT * FROM parameter_info", 1);
	}

	sub get_vcl_infos {
		my ($self, $group_id) = @_;
		
		my $sql = "SELECT name FROM vcl WHERE group_id = ?";
		my $vcl_infos_ref = $dbh->selectall_arrayref($sql, {Slice => {}}, $group_id);
		$sql = "SELECT active_vcl FROM node_group WHERE id = ?";
		my ($active_vcl) = $dbh->selectrow_array($sql, undef, $group_id);
		if (defined($active_vcl)) {
			for my $vcl_info (@$vcl_infos_ref) {
				$vcl_info->{'active'} = ($vcl_info->{'name'} eq $active_vcl);
			}
		}
		
		return $vcl_infos_ref;
	}


	sub get_vcl {
		my ($self, $group_id, $name) = @_;
		
		my $sql = "SELECT vcl FROM vcl WHERE group_id = ? AND name = ?";
		my ($vcl) = $dbh->selectrow_array($sql, undef, $group_id, $name);

		return $vcl;
	}

	sub update_vcl {
		my ($self, $group_id, $name, $vcl) = @_;

		my $sql = "UPDATE vcl SET vcl = ? WHERE group_id = ? AND name = ?";

		return $dbh->do($sql, undef, $vcl, $group_id, $name);
	}

	sub discard_vcl {
		my ($self, $group_id, $name) = @_;

		my $sql = "DELETE FROM vcl WHERE  name = ? and group_id = ?";

		return $dbh->do($sql, undef, $name, $group_id);
	}

	sub add_vcl {
		my ($self, $group_id, $name, $vcl) = @_;

		my $sql = "INSERT INTO vcl(group_id, name, vcl) VALUES(?, ?, ?)";
		$dbh->do($sql, undef, $group_id, $name, $vcl);
		my $vcl_id = $dbh->func('last_insert_rowid');
	}

	sub clean_up {
		my ($self) = @_;

		# 604800 is the number of seconds in a week
		my $timestamp_limit = time()- 604800;
		my $sql = "DELETE FROM stat WHERE time < ?";
		$dbh->do($sql, undef, $timestamp_limit);
	}

	sub finish {
		$dbh->disconnect();
	}
}

1;
