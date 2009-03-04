#!/usr/bin/perl
#
# This script generates the database schema SQL and Varnish::DB_Data module needed
# by the web UI. It connects to the management port of a running Varnish and extracts
# the paramter and stat values.

use strict;

use Varnish::Node;
use Varnish::Util;

# The hostname of the varnish to extract the parameter and stat values from
my $hostname = "localhost";
my $management_port = 9001;


my $node_info_ref = {
	name 			=> 'dummy',
	address			=> $hostname,
	group_id		=> 0,
	management_port	=> $management_port,
};
my $node = Varnish::Node->new($node_info_ref);
if (!$node->get_management()->ping()) {
	print STDERR "Could not contact " . $node_info_ref->{'address'}
			. ":" . $node_info_ref->{'management_port'} . ": " . get_error() . "\n"; 
	exit(-1);
}

my $stat_ref = $node->get_management()->get_stats();
my $stat_fields_exists_string = "my %stat_field_exist = (";
my $stat_fields_sql;
for my $stat (keys(%$stat_ref)) {
	my $name = get_db_friendly_name($stat);
	$stat_fields_sql .= $name . " INTEGER,\n";
	$stat_fields_exists_string .= "'$name' => 1,\n";
}
$stat_fields_exists_string .= ");\n";

my $parameter_ref = $node->get_parameters();
my $parameter_fields_sql;
my $parameter_info_sql;
my $parameters_field_string = "my %parameter_field = (\n";
for my $parameter (sort(keys(%$parameter_ref))) {
	my $name = get_db_friendly_name($parameter);
	if ($name eq "user" || $name eq "group") {
		$name = "child_$name";
	}
	$parameter_fields_sql .= $name . " TEXT,\n";
	my $unit = $parameter_ref->{$parameter}->{'unit'};
	$unit =~ s/'/''/g;
	my $description = $parameter_ref->{$parameter}->{'description'};
	$description =~ s/'/''/g;
	$parameter_info_sql .= sprintf("INSERT INTO parameter_info VALUES('%s', '%s', '%s');\n",
		$name, $unit, $description);

	my $value = $parameter_ref->{$parameter}->{'value'};
	$value =~ s/'/\\'/g;
	$name = get_db_friendly_name($parameter);
	$parameters_field_string .= "'$name' => {value => '$value'},\n";
}
$parameters_field_string .= ");\n";

my $sql = <<"END_SQL";
DROP TABLE node_group;
DROP TABLE node;
DROP TABLE stat;
DROP TABLE parameters;
DROP TABLE parameter_info;
DROP TABLE vcl;

CREATE TABLE node_group (
	id INTEGER PRIMARY KEY,
	active_vcl TEXT,
	name text
);

CREATE TABLE node (
	id INTEGER PRIMARY KEY,
	name TEXT,
	address TEXT,
	port TEXT,
	group_id INTEGER,
	management_port TEXT,
	management_secret TEXT
);

CREATE TABLE stat (
	id INTEGER PRIMARY KEY,
	time TIMESTAMP,
	node_id INTEGER,
$stat_fields_sql
	has_data INTEGER
);

CREATE TABLE parameters (
	id INTEGER PRIMARY KEY,
$parameter_fields_sql
	group_id INTEGER
);

CREATE TABLE vcl(
	group_id INTEGER,
	name TEXT,
	vcl TEXT
);

CREATE TABLE parameter_info(
	name TEXT PRIMARY KEY,
	unit TEXT,
	description TEXT
);

CREATE INDEX stat_time ON stat(time);
CREATE INDEX stat_node_id ON stat(node_id);

INSERT INTO node_group VALUES(0, 0, 'Standalone');

$parameter_info_sql
END_SQL

my $sql_file = "varnish_webui.sql";
open(my $SQL, ">$sql_file") || die "Could not open SQL output file";
print $SQL "-- This file was auto generated " . localtime() . " by create_db_files.pl\n";
print $SQL $sql;
close($SQL);
print "Wrote SQL to $sql_file successfully\n";

my $db_data_file = "Varnish/DB_Data.pm";
open(my $DB_DATA, ">$db_data_file") || die "Could not open DB fields";
print $DB_DATA "# This file was auto generated " . localtime() . " by create_db_files.pl\n";
print $DB_DATA "# DO NOT EDIT BUT RERUN THE SCRIPT!\n"; 
print $DB_DATA "package Varnish::DB_Data;\n\n";
print $DB_DATA $parameters_field_string;
print $DB_DATA $stat_fields_exists_string;
print $DB_DATA "sub get_parameter_field() { return \\%parameter_field; }";
print $DB_DATA "sub get_stat_field_exist() { return \\%stat_field_exist; }";
print $DB_DATA "\n1;\n";
close $DB_DATA;
print "Wrote SQL to $db_data_file successfully\n";
