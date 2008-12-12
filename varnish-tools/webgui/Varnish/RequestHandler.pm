package Varnish::RequestHandler;

use strict;
use warnings;
use HTML::Template;
use HTTP::Request;
use Varnish::Util;
use Varnish::Management;
use Varnish::NodeManager;
use Varnish::Node;
use Varnish::Statistics;
use URI::Escape;
use GD::Graph::lines;
use POSIX qw(strftime);
use List::Util qw(first);
use Socket;

{
	my %request_ref_of;
	my %response_content_ref_of;
	my %response_header_ref_of;
	my %master_tmpl_var_of;

	sub new {
		my ($class, $request_ref, $connection) = @_;

		my $new_object = bless \do{ my $anon_scalar; }, $class;

		$request_ref_of{$new_object} = $request_ref;
		$response_content_ref_of{$new_object} = \"";
		$response_header_ref_of{$new_object} = {};

		my $server_ip = $connection->sockhost();
		my $server_hostname = gethostbyaddr(inet_aton($server_ip), AF_INET);
		$master_tmpl_var_of{$new_object}->{'server_host'} = $server_hostname;
		$master_tmpl_var_of{$new_object}->{'server_port'} = $connection->sockport();

		return $new_object;
	}

	sub DESTROY {
		my ($self) = @_;

		delete $request_ref_of{$self};

		return;
	}

	sub get_response_header {
		my ($self) = @_;

		return $response_header_ref_of{$self};
	}
	sub get_response_content {
		my ($self) = @_;

		return ${$response_content_ref_of{$self}};
	}

	sub _parse_request_parameters {
		my ($content_ref) = @_;
		
		my %parameter = ();
		for my $pair (split /&/,$$content_ref) {
			my ($key,$value) = split /=/,$pair;	
			$value = uri_unescape($value);
			$value =~ s/\+/ /g;
			$parameter{$key} = $value;
		}

		return %parameter;
	}

	sub process {
		my ($self) = @_;

		my $request = ${$request_ref_of{$self}};
		my $operation = $request->uri();
		my $content = $request->content();

		$operation =~ s:^/::;
		if ($operation =~ /^(.*?)\?(.*)/) {
			$operation = $1;
			$content = $2;
		}

		my $content_template;
		my $response_content;
		my %request_parameter = _parse_request_parameters(\$content);

#		while (my ($k, $v) = each %request_parameter) {
#			print "$k => $v\n";
#		}
		
		my $param;
		if ($operation eq 'view_stats' || $operation eq '') {
			($content_template, $param) = view_stats(\%request_parameter);
		}
		elsif ($operation eq 'configure_parameters') {
			($content_template, $param) = configure_parameters(\%request_parameter);
		}
		elsif ($operation eq 'edit_vcl') {
			($content_template, $param) = edit_vcl(\%request_parameter);
		}
		elsif ($operation eq 'node_management') {
			($content_template, $param) = node_management(\%request_parameter);
		}
		elsif ($operation eq 'management_console') {
			($content_template, $param) = management_console(\%request_parameter);
		}
		elsif ($operation eq 'send_management_command') {
			$response_content = send_management_command(\%request_parameter);
		}
		elsif ($operation eq 'generate_graph') {
			$response_header_ref_of{$self}->{'Content-Type'} = "image/png";
			$response_content = generate_graph(\%request_parameter);
			if (!$response_content) {
				$response_content = read_file('images/nograph.png');
			}
		}
		elsif ($operation eq 'collect_data') {
			Varnish::Statistics->collect_data();
			$response_content = "Ok";
		}
		else {
			return;
		}
		
		if ($content_template) {
			my $template_text = read_file("templates/master.tmpl");
			$template_text =~ s/CONTENT_TEMPLATE/$content_template/;

			my $template = HTML::Template->new_scalar_ref(	\$template_text,
					die_on_bad_params => 0);

			my $tmpl_var = $master_tmpl_var_of{$self};
			if ($param) {
				while (my ($parameter, $value) = each %{$param}) {
					$tmpl_var->{$parameter} = $value;
				}
			}
			$template->param($tmpl_var);
			$response_content = $template->output;
		}
		$response_content_ref_of{$self} = \$response_content;
	}

	sub edit_vcl {
		my ($parameter_ref) = @_;

		my %param = %{$parameter_ref};
		$param{'vcl'} ||= "";
		$param{'operation'} ||= "load";
		$param{'group_name'} ||= "";
		$param{'vcl_name'} ||= "";
		$param{'new_vcl_name'} ||= "";


		my $template = "edit_vcl.tmpl";
		my %tmpl_var;
		$tmpl_var{'error'} = "";
		$tmpl_var{'vcl_name'} = $param{'vcl_name'};
		$tmpl_var{'status'} = "";
		$tmpl_var{'vcl_infos'} = [];
		$tmpl_var{'group_infos'} = [];
		$tmpl_var{'vcl_error'} = "";
		$tmpl_var{'vcl'} = "";
		
		my $successfull_save = 0;
		my $editing_new_vcl = 0;

		my @group_masters = Varnish::NodeManager->get_group_masters();
		if ($param{'operation'} eq "make_active") {
			my $group_master = first { 
				$_->get_group() eq $param{'group_name'};
			} @group_masters;

			if ($group_master) {
				my $management = $group_master->get_management();
				if ($management->make_vcl_active($param{'vcl_name'})) {
					my @nodes = Varnish::NodeManager->get_nodes();
					for my $node (@nodes) {
						if ($node != $group_master && $node->get_group() eq $param{'group_name'}) {
							$node->get_management()->make_vcl_active($param{'vcl_name'});
						}
					}
					$tmpl_var{'status'} = "VCL activated successfully";
				}
				else {
					$tmpl_var{'error'} .= "Error activating configuration:\n" . $management->get_error() . "\n";
				}
			}
		}
		elsif ($param{'operation'} eq 'new') {
			if ($param{'new_vcl_name'}) {
				$tmpl_var{'vcl_name'} = $param{'new_vcl_name'};					
				$tmpl_var{'vcl'} = "";
				push @{$tmpl_var{'vcl_infos'}}, {
					name		=> $param{'new_vcl_name'},
					selected	=> 1,
					active		=> 0
				};
				$editing_new_vcl = 1;
			}
		}
		elsif ($param{'operation'} eq 'save') {
			my $group_master = first { 
				$_->get_group() eq $param{'group_name'}
			} @group_masters;

			if ($group_master && $param{'vcl'} ne "" && $param{'vcl_name'} ne "") {
				my $master_management = $group_master->get_management();
				if ($master_management->set_vcl($param{'vcl_name'}, $param{'vcl'})) {
					my @nodes = Varnish::NodeManager->get_nodes();
					for my $node (@nodes) {
						if ($node != $group_master && $node->get_group() eq $param{'group_name'}) {
							my $management = $node->get_management();
							if (!$management->set_vcl($param{'vcl_name'}, $param{'vcl'})) {
								$tmpl_var{'error'} .= "Error saving configuration for " . $node->get_name()
													. ":\n" . $management->get_error() . "\n";
							}
						}
					}
					$successfull_save = 1;
					$tmpl_var{'status'} = "VCL saved successfully";
				}
				else {
					push @{$tmpl_var{'vcl_infos'}}, {
						name		=> $param{'vcl_name'},
						selected	=> 1,
						active		=> 0
					};
					$editing_new_vcl = 1;
					$tmpl_var{'vcl'} = $param{'vcl'};
					my $vcl_error = $master_management->get_error();
					# it is bad bad bad mixing presentation and code, I know, but sometimes you have to
					$vcl_error =~ s/Line (\d+) Pos (\d+)/<a href="javascript:goToPosition($1,$2)">$&<\/a>/g;
					$vcl_error =~ s/\n/<br\/>/g;
					$tmpl_var{'vcl_error'} = $vcl_error;
				}
			}
		}
		elsif ($param{'operation'} eq "discard") {
			my ($group_master) = grep { 
				$_->get_group() eq $param{'group_name'}
			} @group_masters;
			if ($group_master && $param{'vcl_name'} ne "") {
				my $management = $group_master->get_management();
				if ($management->discard_vcl($param{'vcl_name'})) {
					my @nodes = Varnish::NodeManager->get_nodes();
					for my $node (@nodes) {
						if ($node != $group_master && $node->get_group() eq $param{'group_name'}) {
							$node->get_management()->discard_vcl($param{'vcl_name'});
						}
					}

					$tmpl_var{'vcl_name'} = "";
					$tmpl_var{'status'} = "VCL discarded successfully";
				}
				else {
					$tmpl_var{'error'} .= "Error discarding configuration:\n" . $management->get_error() . "\n";
				}
			}
		}
	
		my $selected_group_master;
		for my $group_master (@group_masters) {
			my %group_info = (
					name 		=>	$group_master->get_group(),
					selected	=>	0,
					);
			if ($param{'group_name'} eq $group_master->get_group()) {
				$group_info{'selected'} = '1';
				$selected_group_master = $group_master;
			}
			push @{$tmpl_var{'group_infos'}}, \%group_info;
		}
		if (!$selected_group_master && @group_masters > 0) {
			$selected_group_master = $group_masters[0];
			$tmpl_var{'group_infos'}->[0]->{'selected'} = 1;
		}

		if ($selected_group_master) {
			my $active_vcl_name;
			my @vcl_names;
			my $vcl_names_ref = $selected_group_master->get_management()->get_vcl_names();
			if ($vcl_names_ref) {
				@vcl_names = @{$vcl_names_ref};
				$active_vcl_name = shift @vcl_names;
				
				for my $vcl_name (@vcl_names) {
					my %vcl_info = (
							name 		=>	$vcl_name,
							selected	=>	0,
							active		=>	0,	
							);
					if ($vcl_name eq $tmpl_var{'vcl_name'}) {
						$vcl_info{'selected'} = 1;
						$tmpl_var{'vcl_name'} = $vcl_name;
					}
					if ($vcl_name eq $active_vcl_name) {
						$vcl_info{'active'} = 1;
					}
					push @{$tmpl_var{'vcl_infos'}}, \%vcl_info;
				}
				if ($tmpl_var{'vcl_name'} eq "") {
					FIND_ACTIVE_VCL:
					for my $vcl_info (@{$tmpl_var{'vcl_infos'}}) {
						if ($vcl_info->{'active'}) {
							$tmpl_var{'vcl_name'} = $vcl_info->{'name'};
							$vcl_info->{'selected'} = 1;
							last FIND_ACTIVE_VCL;
						}
					}
					if ($tmpl_var{'vcl_name'} eq "") {
						$tmpl_var{'vcl_name'} = $tmpl_var{'vcl_infos'}->[0]->{'name'};
						$tmpl_var{'vcl_infos'}->[0]->{'selected'} = 1;
					}
				}

				if (!(($param{'operation'} eq 'save' && !$successfull_save
						|| $param{'operation'} eq 'new'))) {
					my $vcl = $selected_group_master->get_management()->get_vcl($tmpl_var{'vcl_name'});
					if ($vcl) {
						$tmpl_var{'vcl'} = $vcl;
					}
					else {
						$tmpl_var{'error'} .= "Error retrieving VCL: " . $selected_group_master->get_management()->get_error() . "\n";
					}
				}
			}
			else {
				$tmpl_var{'error'} .= "Error retrieving the VCLs: " . $selected_group_master->get_management()->get_error();
			}
		}

		$tmpl_var{'editing_new_vcl'} = $editing_new_vcl;
		$tmpl_var{'successfull_save'} = $successfull_save;

		return ($template, \%tmpl_var);
	}


	sub view_stats {
		my ($parameter_ref) = @_;

		my $template = "view_stats.tmpl";

		my %param = %{$parameter_ref};
		$param{'view_raw_stats'} ||= 0;
		$param{'auto_refresh'} ||= 0;

		my %tmpl_var;
		$tmpl_var{'error'} = "";
		$tmpl_var{'stat_time'} = 0;
		$tmpl_var{'node_infos'} = [];
		$tmpl_var{'summary_stats'} = [];
		$tmpl_var{'raw_stats'} = [];
		$tmpl_var{'auto_refresh'} = $param{'toggle_auto_refresh'} ? 1 - $param{'auto_refresh'} : $param{'auto_refresh'};
		$tmpl_var{'auto_refresh_interval'} = $tmpl_var{'auto_refresh'} ? get_config_value('poll_interval') : 0;
		$tmpl_var{'view_raw_stats'} = $param{'view_raw_stats'};

		my $error = "";
	
		my ($stat_time, $stat_ref) = Varnish::Statistics->get_last_measure();
		my @nodes = Varnish::NodeManager->get_nodes();

		if ($stat_time) {
			$stat_time = strftime("%a %b %e %H:%M:%S %Y", localtime($stat_time));
		}

		my %summary_stat_list;
		my %raw_stat_list;
		for my $node (@nodes) {
			push @{$tmpl_var{'node_infos'}}, {
				name	=> $node->get_name(),
			};

			my $node_stat_ref = $stat_ref->{$node};
			my $node_id = $node->get_id();
			my $time_span = 'minute';
			
			# example of adding graph the graph ID must match that of a predefind graph
			# which is created in generate_graph found around line 826
			push @{$summary_stat_list{'Hit ratio'}}, {
				is_graph 	=> 1,
				node_id 	=> $node_id,
				graph_id 	=> 'cache_hit_ratio',
			};
			push @{$summary_stat_list{'Connect requests'}}, {
				is_graph 	=> 1,
				node_id 	=> $node_id,
				graph_id 	=> 'connect_rate',
			};

			# example of missing graph_id
			push @{$summary_stat_list{'Missing graph'}}, {
				is_graph 	=> 1,
				node_id 	=> $node_id,
				graph_id 	=> 'missing_graph',
			};

			# to add custom values, just add values by adding it to the list. The 
			# get_formatted_bytes() function is usefull for displaying byte values
			# as it will convert to MB, GB etc as needed.
			push @{$summary_stat_list{'% of requests served from cache'}}, {
				value	=> get_formatted_percentage($$node_stat_ref{'Cache hits'} 
													, $$node_stat_ref{'Client requests received'})
			};

			# these are examples of adding plain values from the raw stats
			push @{$summary_stat_list{'Client connections accepted'}}, {
				value	=> $$node_stat_ref{'Client connections accepted'}
			};
			push @{$summary_stat_list{'Client requests received'}}, {
				value	=> $$node_stat_ref{'Client requests received'}
			};

			my $total_bytes_served;
			if ($$node_stat_ref{'Total header bytes'} 
				&& $$node_stat_ref{'Total body bytes'}) {
				$total_bytes_served = $$node_stat_ref{'Total header bytes'} + $$node_stat_ref{'Total header bytes'};
			}
			push @{$summary_stat_list{'Total bytes served'}}, {
				'value'	
					=> get_formatted_bytes($total_bytes_served)
			};

			if ($param{'view_raw_stats'}) {
				while (my ($stat_name, $value) = each %{$node_stat_ref}) {
					push @{$raw_stat_list{$stat_name}}, {
						value	=> $value,
					};
				}
			}
		}

		my $row = 1;
		while (my ($stat_name, $values_ref) = each %raw_stat_list) {
			push @{$tmpl_var{'raw_stats'}}, {
				name	=> $stat_name,
				values	=> $values_ref,
				odd_row	=> $row++ % 2,
			}
		}

		$row = 1;
		my $graph_row = 0;
		while (my ($stat_name, $values_ref) = each %summary_stat_list) {
			if ($values_ref->[0]->{'is_graph'}) {
				unshift @{$tmpl_var{'summary_stats'}}, {
					name	=> $stat_name,
					values	=> $values_ref,
					odd_row	=> $graph_row++ % 2,
				}
			}
			else {
				push @{$tmpl_var{'summary_stats'}}, {
					name	=> $stat_name,
					values	=> $values_ref,
					odd_row	=> $row++ % 2,
				}
			}
		}

		$tmpl_var{'error'} = $error;
		$tmpl_var{'stat_time'} = $stat_time;

		return ($template, \%tmpl_var);
	}

	sub configure_parameters {
		my ($parameter_ref) = @_;

		my %param = %{$parameter_ref};
		$param{'node_id'} = $$parameter_ref{'node_id'} || "";
		$param{'group'} = $$parameter_ref{'group'} || "";

		my $template = "configure_parameters.tmpl";
		my %tmpl_var;
		$tmpl_var{'error'} = "";
		$tmpl_var{'status'} = "";
		$tmpl_var{'unit_infos'} = [];
		$tmpl_var{'parameter_infos'} = [];

		my $unit_parameter_ref = {};
		my $error = "";

		my %changed_parameters;
		while (my ($parameter, $value) = each %$parameter_ref) {
			if ($parameter =~ /^new_(.*?)$/ &&
					$$parameter_ref{"old_$1"} ne $value) {
				$changed_parameters{$1} = $value;
			}
		}

		my @nodes = Varnish::NodeManager->get_nodes();
		my @groups = Varnish::NodeManager->get_groups();
		if (%changed_parameters) {
			my $node = first { $_->get_id() eq $param{'node_id'} } @nodes;
			if ($node) {
				my $management = $node->get_management();
				while (my ($parameter, $value) = each %changed_parameters) {
					if (!$management->set_parameter($parameter, $value)) {
						$error .= "Could not set parameter $parameter: ". $node->get_management()->get_error() . "\n";
					}
				}
			}
			else {
				my $group = first { $_ eq $param{'group'} } @groups;
				if ($group ne "") {
					while (my ($parameter, $value) = each %changed_parameters) {
						if (!Varnish::NodeManager->set_group_parameter($group, $parameter, $value)) {
							$error .= "Could not set parameter $parameter for group $group: "
									. Varnish::NodeManager->get_error()  . "\n";
						}
					}
				}
			}
			if ($error eq "") {
				my @changed_parameters = keys %changed_parameters;
				my $status = "Parameter" . (@changed_parameters > 1 ? "s " : " ");

				$status .= shift @changed_parameters;
				for my $parameter (@changed_parameters) {
					$status .= ", $parameter";
				}
				$status .= " configured successfully";
				$tmpl_var{'status'} = $status;
			}
		}

		for my $group (@groups) {
			my %unit_info = (
					name		=>	$group,
					id			=>	$group,
					is_node		=>	0,
					selected	=>	0, 
			);
			if ($group eq $param{'group'}) {
				$unit_info{'selected'} = 1;
				$unit_parameter_ref = Varnish::NodeManager->get_group_parameters($group);
				if (!$unit_parameter_ref) {
					$error .= "Could not get parameters for group $group. You need to have added a node to set these.\n";
				}
			}
			push @{$tmpl_var{'unit_infos'}}, \%unit_info;
		}

		for my $node (@nodes) {
			my %unit_info = (
				name		=>	$node->get_name(),
				id			=>	$node->get_id(),
				is_node		=>	1,
				selected	=>	0, 
			);
			if ($node->get_id() eq $param{'node_id'}) {
				$unit_info{'selected'} = 1;
				$unit_parameter_ref = $node->get_management()->get_parameters();
				if (!$unit_parameter_ref) {
					$error .= "Could not get parameters for node " . $node->get_name() . "\n";
				}
			}
			push @{$tmpl_var{'unit_infos'}}, \%unit_info;
		}

		if ($param{'group'} eq "" && $param{'node_id'} eq ""
			&& @{$tmpl_var{'unit_infos'}} > 0) {
			$tmpl_var{'unit_infos'}->[0]->{'selected'} = 1;
			my $group = $tmpl_var{'unit_infos'}->[0]->{'name'};
			$unit_parameter_ref = Varnish::NodeManager->get_group_parameters($group);
			if (!$unit_parameter_ref) {
				$error .= "Could not get parameters for group $group\n";
			}
		}

		my $row = 0;
		while (my ($parameter, $info) = each %{$unit_parameter_ref} ) {
			my $value = $info->{'value'};
			my $unit = $info->{'unit'};
			my $is_boolean = $unit eq "[bool]";
			if ($is_boolean) {
				$value = $value eq "on";
				$unit = '';
			}
			
			push @{$tmpl_var{'parameter_infos'}}, {
				name 		=> $parameter,
				value 		=> $value,
				unit 		=> $unit,
				description	=> $info->{'description'},
				is_boolean 	=> $is_boolean,
				odd_row 	=> $row++ % 2,
			};
		}

		$tmpl_var{'error'} = $error;
		
		return ($template, \%tmpl_var);
	}


	sub node_management {
		my ($parameter_ref) = @_;

		my %param = %{$parameter_ref};
		$param{'node_id'} ||= "";
		$param{'group'} ||= "";
		$param{'operation'} ||= "";
		$param{'name'} ||= "";
		$param{'address'} = $$parameter_ref{'address'} || "";
		$param{'port'} ||= "";
		$param{'management_port'} ||= "";
	
		my $template = "node_management.tmpl";
		my %tmpl_var = ();
		$tmpl_var{'error'} = "";
		$tmpl_var{'status'} = "";
		$tmpl_var{'add_group'} = 0;
		$tmpl_var{'group_infos'} = [];
		$tmpl_var{'group'} = $param{'group'} || "";
		$tmpl_var{'node_infos'} = [];
		$tmpl_var{'default_managment_port'} = 9001;
		$tmpl_var{'backend_health_infos'} = [];

		my $error = "";
		my $status = "";

		if ($param{'operation'} eq "add_group") {
			if ($param{'group'}) {
				Varnish::NodeManager->add_group($param{'group'});
				 $status .= "Group " . $param{'group'} . " added successfully.";
			}
			else {
				$tmpl_var{'add_group'} = 1;
			}
		}
		elsif ($param{'operation'} eq "remove_group") {
			if ($param{'group'}) {
				Varnish::NodeManager->remove_group($param{'group'});
				$status = "Group " . $param{'group'} . " removed successfully";
				$tmpl_var{'group'} = "";
			}
		}
		elsif ($param{'operation'} eq "start_group") {
			my $node_errors = "";
			for my $node (Varnish::NodeManager->get_nodes()) {
				if ($node->get_group() eq $param{'group'}
						&& !$node->is_running()) {
					my $management = $node->get_management();
					if (!$management->start()) {
						$node_errors .= "Could not start " . $node->get_name() . ": " 
										. $management->get_error() . ". ";
					}
				}
			}

			if ($node_errors eq "") {
				$status .= "Group " . $param{'group'} . " started successfully.";
			}
			else {
				$status .= "Group " . $param{'group'} . " started with errors: $node_errors.";
			}
		}
		elsif ($param{'operation'} eq "stop_group") {
			my $node_errors = "";
			for my $node (Varnish::NodeManager->get_nodes()) {
				if ($node->get_group() eq $param{'group'} 
						&& $node->is_running()) {
					my $management = $node->get_management();
					if (!$management->stop()) {
						$node_errors .= "Could not stop " . $node->get_name() . ": " 
										. $management->get_error() . ". ";
					}
				}
			}
			if ($node_errors eq "") {
				$status .= "Group " . $param{'group'} . " stopped successfully.";
			}
			else {
				$status .= "Group " . $param{'group'} . " stopped with errors: $node_errors.";
			}
		}
		elsif ($param{'operation'} eq 'add_node') {
			if ($param{'name'} && $param{'address'} && $param{'port'} 
				&& $param{'group'} && $param{'management_port'}) {
				my $node = Varnish::Node->new({
					name 			=> $param{'name'}, 
					address			=> $param{'address'},
					port			=> $param{'port'}, 
					group			=> $param{'group'}, 
					management_port	=> $param{'management_port'}
				});
				Varnish::NodeManager->add_node($node);
				$status .= "Node " . $node->get_name() . " added successfully.";
			}
			else {
				$error .= "Not enough information to add node:\n"; 
				$error .= "Name: " . $param{'name'} . ":\n"; 
				$error .= "Address: " . $param{'address'} . ":\n"; 
				$error .= "Port: " . $param{'port'} . ":\n"; 
				$error .= "Group: " . $param{'group'} . ":\n"; 
				$error .= "Management port: " . $param{'management_port'} . ":\n"; 
			}
		}
		elsif ($param{'operation'} eq "remove_node") {
			if ($param{'node_id'}) {
				my $node = Varnish::NodeManager->get_node($param{'node_id'});
				if ($node) {
					$tmpl_var{'group'} = $node->get_group();
					Varnish::NodeManager->remove_node($node);
					$status .= "Node " . $node->get_name() . " removed successfully.";
				}
			}
			else {
				$error .= "Could not remove node: Missing node ID\n";
			}
		}
		elsif ($param{'operation'} eq "start_node") {
			if ($param{'node_id'}) {
				my $node = Varnish::NodeManager->get_node($param{'node_id'});
				if ($node) {
					my $management = $node->get_management();
					if ($node->is_running()) {
						$status .= "Node " . $node->get_name() . " already running.";
					}
					elsif ($management->start() ) {
						$status .= "Node " . $node->get_name() . " started successfully.";
					}
					else {
						$error .= "Could not start " . $node->get_name() 
								. ": " . $management->get_error() . "\n"; 
					}
					$tmpl_var{'group'} = $node->get_group();
				}
			}
			else {
				$error .= "Could not start node: Missing node ID\n";
			}
		}
		elsif ($param{'operation'} eq "stop_node") {
			if ($param{'node_id'}) {
				my $node = Varnish::NodeManager->get_node($param{'node_id'});
				if ($node) {
					my $management = $node->get_management();
					if (!$node->is_running()) {
						$status .= "Node " . $node->get_name() . " already stopped.";
					}
					elsif ($management->stop()) {
						$status .= "Node " . $node->get_name() . " stopped successfully.";
					}
					else {
						$error .= "Could not stop " . $node->get_name() 
								. ": " . $management->get_error() . "\n"; 
					}
				}
				$tmpl_var{'group'} = $node->get_group();
			}
			else {
				$error .= "Could not stop node: Missing node ID\n";
			}
		}

		# Populate the node table
		my @groups = Varnish::NodeManager->get_groups();
		if (@groups) {
			if (!$tmpl_var{'group'} && !$tmpl_var{'add_group'}) {
				$tmpl_var{'group'} = $groups[0];
			}
			my @group_infos = map {
				{
					name		=> $_,
					selected	=> $_ eq $tmpl_var{'group'},
				}
			} @groups;
			$tmpl_var{'group_infos'} = \@group_infos;
			
			my @nodes = Varnish::NodeManager->get_nodes();
			for my $node (@nodes) {
				next if ($node->get_group() ne $tmpl_var{'group'});

				push @{$tmpl_var{'node_infos'}}, {
					id						=> $node->get_id(),	
					is_running_ok			=> $node->is_running_ok(),	
					is_running				=> $node->is_running(),	
					is_management_running	=> $node->is_management_running(),	
					name					=> $node->get_name(),	
					address					=> $node->get_address(),	
					port					=> $node->get_port(),	
					management_port			=> $node->get_management_port(),
					group					=> $node->get_group(),	
				};

				if (@{$tmpl_var{'backend_health_infos'}} == 0) {
					my $backend_health = $node->get_management()->get_backend_health();
					if ($backend_health) {
						while (my ($backend, $health) = each %{$backend_health}) {
							push @{$tmpl_var{'backend_health_infos'}}, {
								name	=> $backend,
								health	=> $health,
							};
						}
					}
				}
			}
		}
		else {
			$tmpl_var{'add_group'} = 1;
		}

		$tmpl_var{'error'} = $error;
		$tmpl_var{'status'} = $status;
		
		return ($template, \%tmpl_var);
	}

sub generate_graph {
	my ($parameter_ref) = @_;

	my %param = %{$parameter_ref};
	$param{'width'} ||= 250;
	$param{'height'} ||= 150;
	$param{'time_span'} ||= "minute";
	$param{'type'} ||= "";
	$param{'node_id'} ||= 0;

	my $interval = get_config_value('poll_interval');

	# this hash holds available graphs which can be added to the summary stats in the view_stats
	# function.
	my %graph_info = (
		# the name of the graph
		cache_hit_ratio	=> {
			# the parameters to GD::Graph. y_number_format should be noted, as it let you format
			# the presentation, like multiplying with 100 to get the percentage as shown here
			graph_parameter	=> {
				y_label			=> '%',
				title			=> "Cache hit ratio last " . $param{'time_span'},
				y_max_value		=> 1,
				y_min_value		=> 0,
				y_number_format	=> sub { return $_[0] * 100 }
			},
			# the divisors and dividends are lists of names of the statistics to
			# use when calculating the values in the graph. The names can be obtained
			# by turning 'Raw statistics' on in the GUI. The value in the graph is calculated
			# by taking the sum of divisors and divide witht the sum of the dividends, i.e.
			# value = (divisor1 + divisor2 + divisor3 ...) / (dividend1 + dividend 2 +..)
			# if divisor or dividend is emitted, the value of 1 is used instead
			divisors			=> [ 'Cache hits' ],
			dividends			=> [ 'Cache hits', 'Cache misses' ],
		},
		connect_rate	=> {
			graph_parameter	=> {
				y_label			=> 'Reqs',
				title			=> "Reqs / $interval s  last " . $param{'time_span'},
				y_min_value		=> 0,
			},
			# here we have no dividends as we only want to plot 'Client requests received'
			divisors			=> [ 'Client requests received' ],
			# if use_delta is set to 1, the derived value is used, i.e. the difference
			# in value between two measurements. This is usefull for graphs showing rates
			# like this connect rate
			use_delta			=> 1,
		},
	);
	my %time_span_graph_parameters  = (
			minute	=> {
				x_label		=> 'Time',
				x_tick_number	=> 6, # need to be set to make x_number_format work
				x_number_format	=> sub { return strftime(":%S", localtime($_[0])); },
				x_max_value		=> time
			},
			hour	=> {
				x_label			=> 'Time',
				x_tick_number	=> 6, # need to be set to make x_number_format work
				x_number_format	=> sub { return strftime("%H:%M", localtime($_[0])); },
			},
			day	=> {
				x_label			=> 'Time',
				x_tick_number	=> 4, # need to be set to make x_number_format work
				x_number_format	=> sub { return strftime("%H", localtime($_[0])); },
			},
			week	=> {
				x_label			=> 'Time',
				x_tick_number	=> 7, # need to be set to make x_number_format work
				x_number_format	=> sub { return strftime("%d", localtime($_[0])); },
			},
			month	=> {
				x_label			=> 'Time',
				x_tick_number	=> 4, # need to be set to make x_number_format work
				x_number_format	=> sub { return strftime("%d.%m", localtime($_[0])); },
			},
			);


	if ( !$graph_info{$param{'type'}} 
		 || !$time_span_graph_parameters{$param{'time_span'}}) {
		#print "Error: Missing data";
		return;
	}
	my $data_ref = Varnish::Statistics->generate_graph_data(
			$param{'node_id'}, 
			$param{'time_span'}, 
			$graph_info{$param{'type'}}->{'divisors'},
			$graph_info{$param{'type'}}->{'dividends'},
			$graph_info{$param{'type'}}->{'use_delta'}
			);
	if (!$data_ref) {
		#print "Error generating graph data\n";
		return;
	}
	my $graph = GD::Graph::lines->new($param{'width'}, $param{'height'});
	$graph->set((%{$graph_info{$param{'type'}}->{'graph_parameter'}}, 
				%{$time_span_graph_parameters{$param{'time_span'}}}),
				dclrs => ["#990200"]);

		my $graph_image = $graph->plot($data_ref);

		if (!$graph_image) {
			return;
		}

		return $graph_image->png;
	}

	sub management_console {
		my ($parameter_ref) = @_;

		my %param = %{$parameter_ref};
		$param{'node_id'} = $$parameter_ref{'node_id'} || 0;

		my $template = "management_console.tmpl";
		my %tmpl_var;
		$tmpl_var{'error'} = "";
		$tmpl_var{'unit_infos'} = [];
		$tmpl_var{'parameter_infos'} = [];
		$tmpl_var{'default_console_font_size'} = '1.1em',
		$tmpl_var{'default_console_cols'} = 80,
		$tmpl_var{'default_console_rows'} = 30,

		my @nodes = Varnish::NodeManager->get_nodes();
		if (@nodes) {
			my $node_id = $param{'node_id'} ? $param{'node_id'} : $nodes[0]->get_id();
			for my $node (@nodes) {
				my $selected = $node->get_id() == $node_id;
				push @{$tmpl_var{'node_infos'}}, {
					id			=> $node->get_id(),
					name		=> $node->get_name(),
					selected	=> $selected,
				};

				if ($selected) {
					$tmpl_var{'current_node_name'} = $node->get_name();
				}
			}
		}
		
		$tmpl_var{'console_themes'} = [
			{
				name		=> 'Grey on black',
				foreground	=> '#bbb',
				background	=> 'black',
			},
			{
				name		=> 'Black on white',
				foreground	=> 'black',
				background	=> 'white',
			},
			{
				name		=> 'Retro',
				foreground	=> 'green',
				background	=> 'black',
			}
		];
		$tmpl_var{'default_console_foreground'}	= $tmpl_var{'console_themes'}->[0]->{'foreground'},
		$tmpl_var{'default_console_background'} = $tmpl_var{'console_themes'}->[0]->{'background'},

		return ($template, \%tmpl_var);
	}

	sub send_management_command {
		my ($parameter_ref) = @_;
		
		my $node_id = $$parameter_ref{'node_id'};
		my $command = $$parameter_ref{'command'};

		if ($node_id && $command) {
			my $node = Varnish::NodeManager->get_node($node_id);
			return "Error: Node not found." if (!$node);
		
			my $management = $node->get_management();
			my $response = $management->send_command($command);
			if ($response) {
				return $response;
			}
			else {
				return "Error: " . $management->get_error();
			}
		}
		else {
			return "Error: Not valid input";
		}
	}

}


1;
