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
use GD::Graph::lines;
use GD qw(gdTinyFont gdSmallFont gdLargeFont gdGiantFont);
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
		$master_tmpl_var_of{$new_object}->{'restricted'} = get_config_value('restricted');

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
			$value = url_decode($value);
			$parameter{$key} = $value;
		}

		return %parameter;
	}

	sub _access_denied {

		return ("access_denied.tmpl", undef);
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
		
		if (0) {
			while (my ($k, $v) = each %request_parameter) {
				print "$k => $v\n";
			}
			print "\n\n";
		}

		my $param;
		my $use_master_template;
		if ($operation eq 'view_stats' || $operation eq '') {
			($content_template, $param, $use_master_template) = view_stats(\%request_parameter);
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
			if (get_config_value('restricted')) {
				($content_template, $param) = _access_denied();
			}
			else {
				$response_content = send_management_command(\%request_parameter);
			}
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
			($content_template, $param) = _access_denied();
		}

		$response_header_ref_of{$self}->{'Connection'} = "Close";
		$use_master_template = 
			defined($use_master_template) ? $use_master_template : 1;
		
		if ($content_template) {
			my $document_root = get_config_value('document_root');
			my %template_options = 
				(die_on_bad_params => 0, global_vars => 1, loop_context_vars => 1, path => [$document_root]);
			if ($use_master_template) {
				my $template_text = read_file("$document_root/templates/master.tmpl");
				$template_text =~ s/CONTENT_TEMPLATE/$content_template/;

				my $template = HTML::Template->new_scalar_ref(	\$template_text,
						%template_options);

				my $tmpl_var = $master_tmpl_var_of{$self};
				if ($param) {
					while (my ($parameter, $value) = each %{$param}) {
						$tmpl_var->{$parameter} = $value;
					}
				}
				$template->param($tmpl_var);
				$response_content = $template->output;
			}
			else {
				my $template = HTML::Template->new_file("templates/$content_template",
						%template_options);

				my $tmpl_var = $master_tmpl_var_of{$self};
				if ($param) {
					while (my ($parameter, $value) = each %{$param}) {
						$tmpl_var->{$parameter} = $value;
					}
				}
				$template->param($tmpl_var);
				$response_content = $template->output;
			}
		}
		$response_content_ref_of{$self} = \$response_content;
	}

	sub edit_vcl {
		my ($parameter_ref) = @_;

		my %param = %{$parameter_ref};
		$param{'vcl'} ||= "";
		$param{'operation'} ||= "load";
		$param{'unit_id'} ||= "";
		$param{'is_node'} ||= "";
		$param{'vcl_name'} ||= "";
		$param{'new_vcl_name'} ||= "";


		my $template = "edit_vcl.tmpl";
		my %tmpl_var;
		$tmpl_var{'error'} = "";
		$tmpl_var{'vcl_name'} = $param{'vcl_name'};
		$tmpl_var{'status'} = "";
		$tmpl_var{'vcl_infos'} = [];
		$tmpl_var{'info_infos'} = [];
		$tmpl_var{'vcl_error'} = "";
		$tmpl_var{'vcl'} = "";
		
		my $successfull_save = 0;
		my $editing_new_vcl = 0;

		if (get_config_value('restricted')
			&& $param{'operation'}
			&& $param{'operation'} ne 'load') {
			return _access_denied();
		}

		if ($param{'operation'} eq "make_active") {
			my $unit;
			if ($param{'is_node'}) {
				$unit = Varnish::NodeManager->get_node($param{'unit_id'});
			}
			else {
				$unit = Varnish::NodeManager->get_group($param{'unit_id'});
			}
			if ($unit) {
				if ($unit->make_vcl_active($param{'vcl_name'})) {
					$tmpl_var{'status'} = "VCL activated successfully";
					log_info("[" . $unit->get_name() . "] [Make VCL active] [" . 
							$param{'vcl_name'} . "]");
				}
				else {
					$tmpl_var{'error'} .= "Error activating configuration:\n" . get_error() . "\n";
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
			my $unit;
			if ($param{'is_node'}) {
				$unit= Varnish::NodeManager->get_node($param{'unit_id'});
			}
			else {
				$unit= Varnish::NodeManager->get_group($param{'unit_id'});
			}
			if ($unit && $param{'vcl'} ne "" && $param{'vcl_name'} ne "") {
				my $existing_vcl = $unit->get_vcl($param{'vcl_name'});
				if ($unit->save_vcl($param{'vcl_name'}, $param{'vcl'})) {
					my $diff = diff($existing_vcl, $param{'vcl'});
					$successfull_save = 1;
					$tmpl_var{'status'} = "VCL saved successfully";
					log_info("[" . $unit->get_name() . "] [Saved VCL] [" . 
							$param{'vcl_name'} . "] ["
							. url_encode($diff) . "]");
				}
				else {
					$editing_new_vcl = 1;
					$tmpl_var{'vcl'} = $param{'vcl'};
					push @{$tmpl_var{'vcl_infos'}}, {
						name		=> $param{'new_vcl_name'},
						selected	=> 1,
						active		=> 0
					};
					my $vcl_error = get_error();
					# it is bad bad bad mixing presentation and code, I know, but sometimes you have to
					$vcl_error =~ s/Line (\d+) Pos (\d+)/<a href="javascript:goToPosition($1,$2)">$&<\/a>/g;
					$vcl_error =~ s/\n/<br\/>/g;
					$tmpl_var{'vcl_error'} = $vcl_error;
				}
			}
		}
		elsif ($param{'operation'} eq "discard") {
			my $unit;
			if ($param{'is_node'}) {
				$unit= Varnish::NodeManager->get_node($param{'unit_id'});
			}
			else {
				$unit= Varnish::NodeManager->get_group($param{'unit_id'});
			}
			if ($unit && $param{'vcl_name'} ne "") {
				if ($unit->discard_vcl($param{'vcl_name'})) {

					$tmpl_var{'vcl_name'} = "";
					$tmpl_var{'status'} = "VCL discarded successfully";
					log_info("[" . $unit->get_name() . "] [Discarded VCL] [" . 
							$param{'vcl_name'} . "]");
				}
				else {
					$tmpl_var{'error'} .= "Error discarding configuration:\n" . get_error() . "\n";
				}
			}
		}
	
		my $groups_ref = Varnish::NodeManager->get_groups();
		my $nodes_ref = Varnish::NodeManager->get_nodes(Varnish::NodeManager->get_group(0));
		my $selected_unit;
		for my $unit (@$groups_ref, @$nodes_ref) {
			my $is_node = ref($unit) eq "Varnish::Node";
			next if (!$is_node && $unit->get_id() == 0);
			
			my $selected = 0;
			if (!$selected_unit && 
				(!$param{'unit_id'}
				|| ($is_node && $param{'is_node'} && $param{'unit_id'} == $unit->get_id())
				|| (!$is_node && !$param{'is_node'} && $param{'unit_id'} == $unit->get_id()))) {
				$selected_unit = $unit;
				$selected = 1;
			}
			my %unit_info = (
					id			=>	$unit->get_id(),
					is_node		=>	$is_node,
					name 		=>	$unit->get_name(),
					selected	=>	$selected,
			);
			push @{$tmpl_var{'unit_infos'}}, \%unit_info;
		}
		if ($selected_unit) {
			my $vcl_infos_ref = $selected_unit->get_vcl_infos();
			if ($vcl_infos_ref) {
				push @{$tmpl_var{'vcl_infos'}}, @$vcl_infos_ref;
				if ($tmpl_var{'vcl_name'}) {
					for my $vcl_info_ref (@{$tmpl_var{'vcl_infos'}}) {
						if ($vcl_info_ref->{'name'} eq $tmpl_var{'vcl_name'}) {
							$vcl_info_ref->{'selected'} = 1;
						}
					}
				}
				else {
					my $active_found = 0;
FIND_ACTIVE_VCL:
					for my $vcl_info (@{$tmpl_var{'vcl_infos'}}) {
						if ($vcl_info->{'active'}) {
							$tmpl_var{'vcl_name'} = $vcl_info->{'name'};
							$vcl_info->{'selected'} = 1;
							$active_found = 1;
							last FIND_ACTIVE_VCL;
						}
					}
					if (!$active_found && @{$tmpl_var{'vcl_infos'}} > 0) {
						my $vcl_info = $tmpl_var{'vcl_infos'}->[0]; 

						$tmpl_var{'vcl_name'} = $vcl_info->{'name'};
						$vcl_info->{'selected'} = 1;
					}
				}
			}

			if ($tmpl_var{'vcl_name'} &&
				!(($param{'operation'} eq 'save' && !$successfull_save
					|| $param{'operation'} eq 'new'))) {
				my $vcl = $selected_unit->get_vcl($tmpl_var{'vcl_name'});
				if ($vcl) {
					$tmpl_var{'vcl'} = $vcl;
				}
				else {
					$tmpl_var{'error'} .= "Error retrieving VCL: " . get_error() . "\n";
				}
			}
		}

		$tmpl_var{'editing_new_vcl'} = $editing_new_vcl;
		$tmpl_var{'successfull_save'} = $successfull_save;

		return ($template, \%tmpl_var);
	}
	
	sub view_stats_csv{
		my ($show_group, $csv_delim) = @_;
		$csv_delim ||= ",";

		my $template = "view_stats_csv.tmpl";
		my %tmpl_var;	
		$tmpl_var{'rows'} = [];
		$tmpl_var{'stat_time'} = '';
		
		my @stat_names;
		my $first_row = 1;
		my $nodes_ref = [];
		my $groups_ref = [];
		if ($show_group > 0) {
			my $group = Varnish::NodeManager->get_group($show_group);
			push @$groups_ref, $group;
			$nodes_ref = Varnish::NodeManager->get_nodes($group);
		}
		else {
			$groups_ref = Varnish::NodeManager->get_groups();
			$nodes_ref = Varnish::NodeManager->get_nodes();
		}
		for my $unit (@$groups_ref, @$nodes_ref) {
			next if (ref($unit) eq "Varnish::Group" && $unit->get_id() == 0);
			my ($stat_time, $stat_ref) = Varnish::Statistics->get_last_measure($unit);
			if ($first_row) {
				@stat_names = keys(%$stat_ref);
				my @column_names = map { {value => $_} } @stat_names;
				push @{$tmpl_var{'rows'}}, {
					values	=> \@column_names,
					unit	=> "name",
				};
				if ($stat_time) {
					$stat_time = strftime("%a %b %e %H:%M:%S %Y", localtime($stat_time));
				}
				$first_row = 0;
			}
			my @values = map { {value => $stat_ref->{$_}} } @stat_names;
			push @{$tmpl_var{'rows'}}, {
				values	=> \@values,
				unit	=> $unit->get_name(),
			};
		}
	
		return ($template, \%tmpl_var, 0);
	}

	sub _get_stat {
		my ($name, $stat_ref) = @_;

		return $stat_ref->{get_db_friendly_name($name)};
	}

	sub view_stats {
		my ($parameter_ref) = @_;

		my $template = "view_stats.tmpl";

		my %param = %{$parameter_ref};
		$param{'view_raw_stats'} ||= 0;
		$param{'auto_refresh'} ||= 0;
		$param{'show_group'} ||= 0;
		$param{'csv'} ||= 0;

		if ($param{'csv'}) {
			return view_stats_csv($param{'show_group'});
		}

		my %tmpl_var;
		$tmpl_var{'error'} = '';
		$tmpl_var{'stat_time'} = '';
		$tmpl_var{'unit_infos'} = [];
		$tmpl_var{'summary_stats'} = [];
		$tmpl_var{'raw_stats'} = [];
		$tmpl_var{'auto_refresh'} = $param{'toggle_auto_refresh'} ? 1 - $param{'auto_refresh'} : $param{'auto_refresh'};
		$tmpl_var{'auto_refresh_interval'} = $tmpl_var{'auto_refresh'} ? get_config_value('poll_interval') : 0;
		$tmpl_var{'view_raw_stats'} = $param{'view_raw_stats'};
		$tmpl_var{'graph_width'} = get_config_value('graph_width');
		$tmpl_var{'graph_height'} = get_config_value('graph_height');
		$tmpl_var{'large_graph_width'} = get_config_value('large_graph_width');
		$tmpl_var{'large_graph_height'} = get_config_value('large_graph_height');
		$tmpl_var{'show_group'} = $param{'show_group'};
		$tmpl_var{'group_name'} = '';

		my $error = "";
	
		my %summary_stat_list;
		my %raw_stat_list;
		my $nodes_ref = [];
		my $groups_ref = [];
		if ($tmpl_var{'show_group'} > 0) {
			my $group = Varnish::NodeManager->get_group($tmpl_var{'show_group'});
			push @$groups_ref, $group;
			$tmpl_var{'group_name'} = $group->get_name();
			$nodes_ref = Varnish::NodeManager->get_nodes($group);
		}
		else {
			$groups_ref = Varnish::NodeManager->get_groups();
			my $standalone_group = Varnish::NodeManager->get_group(0);
		 	$nodes_ref = Varnish::NodeManager->get_nodes($standalone_group);
		}
		for my $unit (@$groups_ref, @$nodes_ref) {
			my $unit_id;
			my $is_node;
			if (ref($unit) eq "Varnish::Node") {
				$unit_id = $unit->get_id();
				$is_node = 1;
			}
			else {
				$unit_id = $unit->get_id();
				$is_node = 0;
				next if ($unit_id <= 0);
			}
			my $time_span = 'minute';
			my ($stat_time, $stat_ref) = Varnish::Statistics->get_last_measure($unit);

			next if (!$stat_ref);

			my $running;
			my $all_running;
			if ($is_node) {
				$running = $all_running = $unit->is_running_ok();
			}
			else {
				my $nodes_ref = Varnish::NodeManager->get_nodes($unit);
				my $running_ok = 0;
				for my $node (@$nodes_ref) {
					if ($node->is_running_ok()) {
						$running_ok++;
					}
				}
				$running = $running_ok > 0;
				$all_running = $running_ok == @$nodes_ref;
			}


			push @{$tmpl_var{'unit_infos'}}, {
				name			=> $unit->get_name(),
				unit_id			=> $unit_id,
				group_id		=> ($is_node ? $unit->get_group_id() : $unit_id),
				is_node			=> $is_node,
				running			=> $running,
				all_running 	=> $all_running,
			};

			if (!$tmpl_var{'stat_time'}) {
				$tmpl_var{'stat_time'} = strftime("%a %b %e %H:%M:%S %Y", localtime($stat_time));
			}
			
			# example of adding graph the graph ID must match that of a predefind graph
			# which is created in generate_graph found around line 826
			push @{$summary_stat_list{'Hit ratio since start'}}, {
				is_graph 	=> 1,
				unit_id 	=> $unit_id,
				is_node 	=> $is_node,
				graph_id 	=> 'cache_hit_ratio_since_start',
			};
			push @{$summary_stat_list{'Hit ratio'}}, {
				is_graph 	=> 1,
				unit_id 	=> $unit_id,
				is_node 	=> $is_node,
				graph_id 	=> 'cache_hit_ratio',
			};
			push @{$summary_stat_list{'Connect requests'}}, {
				is_graph 	=> 1,
				unit_id 	=> $unit_id,
				is_node 	=> $is_node,
				graph_id 	=> 'connect_rate',
			};

			# to add custom values, just add values by adding it to the list. The 
			# get_formatted_bytes() function is usefull for displaying byte values
			# as it will convert to MB, GB etc as needed.
			push @{$summary_stat_list{'Hit ratio since start (%)'}}, {
				value	=> get_formatted_percentage(_get_stat('Cache hits', $stat_ref) 
													, _get_stat('Client requests received', $stat_ref))
			};

			# these are examples of adding plain values from the raw stats
			push @{$summary_stat_list{'Client requests received'}}, {
				value	=> _get_stat('Client requests received', $stat_ref)
			};

			my $total_bytes_served;
			my $total_header_bytes = _get_stat('Total header bytes', $stat_ref);
			my $total_body_bytes = _get_stat('Total body bytes', $stat_ref);
			if (defined($total_header_bytes) && defined($total_body_bytes)) {
				$total_bytes_served = $total_header_bytes + $total_body_bytes;
			}
			push @{$summary_stat_list{'Total bytes served'}}, {
				'value'	
					=> get_formatted_bytes($total_bytes_served)
			};

			if ($param{'view_raw_stats'}) {
				while (my ($stat_name, $value) = each %{$stat_ref}) {
					push @{$raw_stat_list{$stat_name}}, {
						value	=> $value,
						unit_id	=> $unit_id,
						is_node	=> $is_node,
					};
				}
			}
		}

		my @stat_names = sort(keys(%raw_stat_list));
		for my $stat_name (@stat_names) {
			push @{$tmpl_var{'raw_stats'}}, {
				name	=> $stat_name,
				values	=> $raw_stat_list{$stat_name},
			}
		}

		while (my ($stat_name, $values_ref) = each %summary_stat_list) {
			if ($values_ref->[0]->{'is_graph'}) {
				unshift @{$tmpl_var{'summary_stats'}}, {
					name	=> $stat_name,
					values	=> $values_ref,
				}
			}
			else {
				push @{$tmpl_var{'summary_stats'}}, {
					name	=> $stat_name,
					values	=> $values_ref,
				}
			}
		}

		$tmpl_var{'error'} = $error;

		return ($template, \%tmpl_var);
	}

	sub configure_parameters {
		my ($parameter_ref) = @_;

		my %param = %{$parameter_ref};
		$param{'node_id'} = -1 if (!defined($param{'node_id'}));
		$param{'group_id'} = -1 if (!defined($param{'group_id'}));

		my $template = "configure_parameters.tmpl";
		my %tmpl_var;
		$tmpl_var{'error'} = "";
		$tmpl_var{'status'} = "";
		$tmpl_var{'unit_infos'} = [];
		$tmpl_var{'parameter_infos'} = [];

		my $unit_parameter_ref = {};
		my $error = "";

		my %changed_parameter;
		while (my ($parameter, $value) = each %$parameter_ref) {
			if ($parameter =~ /^new_(.*?)$/ &&
					$$parameter_ref{"old_$1"} ne $value) {
				
				$changed_parameter{$1}->{'old_value'} = $$parameter_ref{"old_$1"};
				$changed_parameter{$1}->{'value'} = $value;
			}
		}

		my $nodes_ref = Varnish::NodeManager->get_nodes();
		my $groups_ref = Varnish::NodeManager->get_groups();
		if (%changed_parameter) {
			if (get_config_value('restricted')) {
				return _access_denied();
			}

			my $unit_name;
			my $node = Varnish::NodeManager->get_node($param{'node_id'});
			if ($node) {
				$node->update_parameters(\%changed_parameter);
				$unit_name = $node->get_name();
			}
			else {
				my $group = Varnish::NodeManager->get_group($param{'group_id'});
				if ($group) {
					$unit_name = $group->get_name();
					$group->update_parameters(\%changed_parameter);
				}
			}
			if ($error eq "") {
				my @changed_parameters = keys %changed_parameter;
				my $status;
				
				for my $parameter (@changed_parameters) {
					my $change;
					
					$change .= $changed_parameter{$parameter}->{'old_value'} . ' => ';
					$change .= $changed_parameter{$parameter}->{'value'};
					if ($status) {
						$status .= ", ";
					}
					$status .= "$parameter ($change)";
					log_info("[$unit_name] [Parameter change] [$parameter] [$change]");
				}
				$status = "Parameter" . (@changed_parameters > 1 ? "s " : " ") . $status;
				$status .= " configured successfully";
				
				$tmpl_var{'status'} = $status;
			}
		}

		for my $group (@$groups_ref) {
			next if $group->get_id() == 0;

			my %unit_info = (
					id			=>	$group->get_id(),
					name		=>	$group->get_name(),
					is_node		=>	0,
					selected	=>	0, 
			);
			if ($group->get_id() eq $param{'group_id'}) {
				$unit_info{'selected'} = 1;
				$unit_parameter_ref = $group->get_parameters();
				if (!$unit_parameter_ref) {
					$error .= "Could not get parameters for group $group. You need to have added a node to set these.\n";
				}
			}
			push @{$tmpl_var{'unit_infos'}}, \%unit_info;
		}

		for my $node (@$nodes_ref) {
			my %unit_info = (
				name		=>	$node->get_name(),
				id			=>	$node->get_id(),
				is_node		=>	1,
				selected	=>	0, 
			);
			if ($node->get_id() eq $param{'node_id'}) {
				$unit_info{'selected'} = 1;
				$unit_parameter_ref = $node->get_parameters();
				if (!$unit_parameter_ref) {
					$error .= "Could not get parameters for node " . $node->get_name() . "\n";
				}
			}
			push @{$tmpl_var{'unit_infos'}}, \%unit_info;
		}

		if ($param{'group_id'} < 0 && $param{'node_id'} < 0 
			&& @{$tmpl_var{'unit_infos'}} > 0) {
			$tmpl_var{'unit_infos'}->[0]->{'selected'} = 1;
			my $id = $tmpl_var{'unit_infos'}->[0]->{'id'};
			if ($tmpl_var{'unit_infos'}->[0]->{'is_node'}) {
				$unit_parameter_ref = Varnish::NodeManager->get_node($id)->get_parameters();
			}
			else {
				$unit_parameter_ref = Varnish::NodeManager->get_group($id)->get_parameters();
			}
		}

		my @parameters = sort(keys(%$unit_parameter_ref));
		for my $parameter (@parameters) {
			my $info = $unit_parameter_ref->{$parameter};
			my $value = $info->{'value'};
			my $unit = $info->{'unit'};
			my $is_boolean = $unit && $unit eq "bool";
			if ($is_boolean) {
				$value = $value && $value eq "on";
				$unit = '';
			}
		
#			my $description = $info->{'description'};
#			$description =~ s/'/''/g;
#			print "INSERT INTO parameter_info(name, unit, description) values('$parameter', '$unit', '$description');\n";

			push @{$tmpl_var{'parameter_infos'}}, {
				name 		=> $parameter,
				value 		=> $value,
				unit 		=> $unit,
				description	=> $info->{'description'},
				is_boolean 	=> $is_boolean,
			};
		}

		$tmpl_var{'error'} = $error;
		
		return ($template, \%tmpl_var);
	}


	sub node_management {
		my ($parameter_ref) = @_;

		my %param = %{$parameter_ref};
		$param{'node_id'} = -1 if (!defined($param{'node_id'}));
		$param{'group_id'} = -1 if (!defined($param{'group_id'}));
		$param{'group_name'} ||= "";
		$param{'operation'} ||= "";
		$param{'name'} ||= "";
		$param{'address'} = $$parameter_ref{'address'} || "";
		$param{'port'} ||= "";
		$param{'management_port'} ||= "";
		$param{'inheritance'} ||= 0;
		$param{'edit_node'} ||= -1;
	
		my $template = "node_management.tmpl";
		my %tmpl_var = ();
		$tmpl_var{'error'} = "";
		$tmpl_var{'status'} = "";
		$tmpl_var{'add_group'} = 0;
		$tmpl_var{'group_infos'} = [];
		$tmpl_var{'group_id'} = $param{'group_id'};
		$tmpl_var{'node_infos'} = [];
		$tmpl_var{'default_managment_port'} = 9001;
		$tmpl_var{'backend_health_infos'} = [];
		$tmpl_var{'show_group_controls'} = 1;
		$tmpl_var{'show_group'} = 0;
		$tmpl_var{'show_add_node'} = 1;
		$tmpl_var{'show_node_in_backend_health'} = 1;
		$tmpl_var{'show_inheritance_settings'} = 1;
		$tmpl_var{'inheritance_settings'} = [];

		my $error = "";
		my $status = "";

		if (get_config_value('restricted')
			&& $param{'operation'} ne '') {
			return _access_denied();
		}

		if ($param{'operation'} eq "add_group") {
			if ($param{'group_name'}) {
				my $new_group = Varnish::Group->new({name => $param{'group_name'}});
				Varnish::NodeManager->add_group($new_group);
				$tmpl_var{'group_id'} = $new_group->get_id();
				$status .= "Group " . $param{'group_name'} . " added successfully.";
				log_info("[" . $param{'group_name'} . "] [Added group]");
			}
			else {
				$tmpl_var{'group_id'} = -2;
				$tmpl_var{'add_group'} = 1;
			}
		}
		elsif ($param{'operation'} eq "remove_group") {
			if ($param{'group_id'} >= 0) {
				my $group = Varnish::NodeManager->get_group($param{'group_id'});
				if (Varnish::NodeManager->remove_group($group)) {
					$status = "Group ". $group->get_name() . " removed successfully";
					log_info("[" . $group->get_name() . "] [Removed group]");
				}
				else {
					$error = "Error removing group " . $group->get_name() . ": " . get_error();
				}
				$tmpl_var{'group_id'} = -1;
			}
		}
		elsif ($param{'operation'} eq "start_group") {
			my $group = Varnish::NodeManager->get_group($param{'group_id'});
			if ($group->start()) {
				$status .= "Group " . $group->get_name() . " started successfully.";
				log_info("[" . $group->get_name() . "] [Started group]");
			}
			else {
				$status .= "Group " . $group->get_name() . " started with errors: " . get_error();
			}
		}
		elsif ($param{'operation'} eq "stop_group") {
			my $group = Varnish::NodeManager->get_group($param{'group_id'});
			if ($group->stop()) {
				$status .= "Group " . $group->get_name() . " stopped successfully.";
				log_info("[" . $group->get_name() . "] [Stopped group]");
			}
			else {
				$status .= "Group " . $group->get_name() . " started with errors: " . get_error();
			}
		}
		elsif ($param{'operation'} eq "rename_group") {
			my $group = Varnish::NodeManager->get_group($param{'group_id'});
			if ($group && $param{'group_name'}) {
				my $old_name = $group->get_name();

				$group->set_name($param{'group_name'});
				Varnish::NodeManager->update_group($group);
				log_info("[" . $group->get_name() . "] [Renamed group] [$old_name => "
					. $group->get_name() . "]");
			}
		}
		elsif ($param{'operation'} eq 'add_node') {
			if ($param{'name'} && $param{'address'} && $param{'port'} 
				&& $param{'group_id'} >= 0 && $param{'management_port'}) {
				my $node = Varnish::Node->new({
					name 			=> $param{'name'}, 
					address			=> $param{'address'},
					port			=> $param{'port'}, 
					group_id		=> $param{'group_id'}, 
					management_port	=> $param{'management_port'}
				});
				Varnish::NodeManager->add_node($node, $param{'inheritance'});
				$status .= "Node " . $node->get_name() . " added successfully.";
				
				my $group = Varnish::NodeManager->get_group($param{'group_id'});
				my $group_name = ($group ? $group->get_name() : "");
				my $inheritance = ($param{'inheritance'} == 0 ? "None"	:
								   $param{'inheritance'} == 1 ? "Group inherited node" :
								   "Node inherited group");
				log_info("[" . $node->get_name() . "] [Added node]"
					. " [name=" . $node->get_name() . "]"
					. " [address=" . $node->get_address() . "]"
					. " [port=" . $node->get_port() . "]"
					. " [group=" . $group_name . "]"
					. " [management_port=" . $node->get_management_port() . "]"
					. " [settings_inheritance=$inheritance]");
			}
			else {
				$error .= "Not enough information to add node:\n"; 
				$error .= "Name: " . $param{'name'} . ":\n"; 
				$error .= "Address: " . $param{'address'} . ":\n"; 
				$error .= "Port: " . $param{'port'} . ":\n"; 
				$error .= "Management port: " . $param{'management_port'} . ":\n"; 
			}
		}
		elsif ($param{'operation'} eq 'update_node') {
			my $node = Varnish::NodeManager->get_node($param{'node_id'});
			
			if ($node) {
				$node->set_name($param{'name'});
				$node->set_address($param{'address'});
				$node->set_port($param{'port'});
				$node->set_group_id($param{'node_group_id'});
				$node->set_management_port($param{'management_port'});
				
				Varnish::NodeManager->update_node($node);

				$status .= "Node " . $node->get_name() . " updated successfully.";

				my $group = Varnish::NodeManager->get_group($param{'node_group_id'});
				my $group_name = ($group ? $group->get_name() : "");
				log_info("[" . $node->get_name() . "] [Updated node]"
					. " [name=" . $node->get_name() . "]"
					. " [address=" . $node->get_address() . "]"
					. " [port=" . $node->get_port() . "]"
					. " [group=" . $group_name . "]"
					. " [management_port=" . $node->get_management_port() . "]");
			}
		}

		elsif ($param{'operation'} eq "remove_node") {
			if ($param{'node_id'} >= 0) {
				my $node = Varnish::NodeManager->get_node($param{'node_id'});
				if ($node) {
					$tmpl_var{'group_id'} = $node->get_group_id();
					Varnish::NodeManager->remove_node($node);
					$status .= "Node " . $node->get_name() . " removed successfully.";
					log_info("[" . $node->get_name() . "] [Removed node]");
				}
			}
			else {
				$error .= "Could not remove node: Missing node ID\n";
			}
		}
		elsif ($param{'operation'} eq "start_node") {
			if ($param{'node_id'} >= 0) {
				my $node = Varnish::NodeManager->get_node($param{'node_id'});
				if ($node) {
					if ($node->start() ) {
						$status .= "Node " . $node->get_name() . " started successfully.";
						log_info("[" . $node->get_name() . "] [Started node]");
					}
					else {
						$error .= "Could not start " . $node->get_name() 
								. ": " . get_error() . "\n"; 
					}
					$tmpl_var{'group_id'} = $node->get_group_id();
				}
			}
			else {
				$error .= "Could not start node: Missing node ID\n";
			}
		}
		elsif ($param{'operation'} eq "stop_node") {
			if ($param{'node_id'} >= 0) {
				my $node = Varnish::NodeManager->get_node($param{'node_id'});
				if ($node) {
					if ($node->stop()) {
						$status .= "Node " . $node->get_name() . " stopped successfully.";
						log_info("[" . $node->get_name() . "] [Stopped node]");
					}
					else {
						$error .= "Could not stop " . $node->get_name() 
								. ": " . get_error() . "\n"; 
					}
				}
				$tmpl_var{'group_id'} = $node->get_group_id();
			}
			else {
				$error .= "Could not stop node: Missing node ID\n";
			}
		}

		# Populate the node table
		my $groups_ref = Varnish::NodeManager->get_groups();
		if ($groups_ref) {
			my @group_infos = map {
				{
					name		=> $_->get_name(),
					id			=> $_->get_id(),
					is_real		=> $_->get_id() >= 0,
					selected	=> $_->get_id() eq $tmpl_var{'group_id'},
				}
			} @$groups_ref;
			unshift @group_infos, {
					name		=> "All nodes",
					id			=> -1,
					selected	=> -1 == $tmpl_var{'group_id'},
			};
			$tmpl_var{'group_infos'} = \@group_infos;
		
			my $group;
			my $nodes_ref;
			if ($tmpl_var{'group_id'} != -1) {
				$group = Varnish::NodeManager->get_group($tmpl_var{'group_id'});
				$nodes_ref = Varnish::NodeManager->get_nodes($group);
			}
			else {
				$nodes_ref = Varnish::NodeManager->get_nodes();
			}
			for my $node (@$nodes_ref) {
				my $group_name = ($group ? $group->get_name() 
										 : Varnish::NodeManager->get_group_name($node->get_group_id));
				my $node_info_ref = {
					id						=> $node->get_id(),	
					is_running_ok			=> $node->is_running_ok(),	
					is_running				=> $node->is_running(),	
					is_management_running	=> $node->is_management_running(),	
					name					=> $node->get_name(),	
					address					=> $node->get_address(),	
					port					=> $node->get_port(),	
					management_port			=> $node->get_management_port(),
					group					=> $group_name,
					edit					=> $node->get_id() == $param{'edit_node'},
				};
				my $backend_health = $node->get_backend_health();
				if ($backend_health) {
					while (my ($backend, $health) = each %{$backend_health}) {
						push @{$tmpl_var{'backend_health_infos'}}, {
							name	=> $backend,
							health	=> $health,
							node	=> $node_info_ref->{'name'},
						};
					}
				}
				push @{$tmpl_var{'node_infos'}}, $node_info_ref;
			}
		}
		else {
			$tmpl_var{'add_group'} = 1;
		}

		if ($tmpl_var{'group_id'} > 0) {
			my @inheritance_settings;
			push @inheritance_settings, {
				value		=>  2,
							name		=> "Node inherits group",
							selected 	=> @{$tmpl_var{'node_infos'}} > 0,
			};
			push @inheritance_settings, {
				value		=> 1,
							name		=> "Group inherits node",
							selected 	=> @{$tmpl_var{'node_infos'}} == 0,
			};
			push @inheritance_settings, {
				value		=> 0,
							name		=> "No inheritance",
							selected 	=> 0,
			};
			$tmpl_var{'inheritance_settings'} = \@inheritance_settings;
		}
		else {
			$tmpl_var{'show_inheritance_settings'} = 0;
		}


		my $selected_group = Varnish::NodeManager->get_group($tmpl_var{'group_id'});
		if ($selected_group) {
			$tmpl_var{'group_name'} = $selected_group->get_name();
		}
		$tmpl_var{'show_group_controls'} = $tmpl_var{'group_id'} > 0;
		$tmpl_var{'show_group'} = $tmpl_var{'group_id'} == -1 || $param{'edit_node'} > -1;
		$tmpl_var{'show_add_node'} = $tmpl_var{'group_id'} >= 0;
		$tmpl_var{'error'} = $error;
		$tmpl_var{'status'} = $status;
		
		return ($template, \%tmpl_var);
	}

	sub generate_graph {
		my ($parameter_ref) = @_;

		my %param = %{$parameter_ref};
		$param{'width'} ||= get_config_value('graph_width');
		$param{'height'} ||= get_config_value('graph_height');
		$param{'time_span'} ||= "minute";
		$param{'unit_id'} ||= -1;
		$param{'custom_name'} ||= "";
		$param{'custom_divisors'} ||= "";
		$param{'custom_dividends'} ||= "";
		$param{'custom_delta'} ||= "";


		my $interval = get_config_value('poll_interval');

		# this hash holds available graphs which can be added to the summary stats in the view_stats
		# function.
		my %graph_info = (
			# the name of the graph
			cache_hit_ratio_since_start	=> {
				# the parameters to GD::Graph. y_number_format should be noted, as it let you format
				# the presentation, like multiplying with 100 to get the percentage as shown here
				graph_parameter	=> {
					y_label			=> '%',
					title			=> 'Cache hit ratio since start',
					y_max_value		=> 1,
					#y_min_value		=> 0,
					y_number_format	=> sub { return sprintf("%.2f", $_[0] * 100) }
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
					title			=> "Reqs / s last " . $param{'time_span'},
					y_min_value		=> 0,
				},
				# here we have no dividends as we only want to plot 'Client requests received'
				divisors			=> [ 'Client requests received' ],
				# if use_delta is set to 1, the derived value is used, i.e. the difference
				# in value between two measurements. This is usefull for graphs showing rates
				# like this connect rate
				use_delta			=> 1,
			},
			cache_hit_ratio 	=> {
				graph_parameter	=> {
					y_label			=> '%',
					title			=> "Cache hit last " . $param{'time_span'},
					y_number_format	=> sub { return sprintf("%.2f", $_[0] * 100) }
				},
				divisors			=> [ 'Cache hits' ],
				dividends			=> [ 'Cache hits', 'Cache misses' ],
				# with use_delta set to 2, the delta is calculated by doing
				# (divsor(n) - divisor(n-1))/(dividend(n) - dividend(n-1))
				# instead of
				# ((divisor(n)/dividend(n-1) - (divisor(n-1)/dividend(n-1)
				# in the case
				# of use_delta = 1
				use_delta			=> 2,
			},
			custom				=> {
				graph_parameter => {
					y_label 		=> 'Value',
					title			=> $param{'custom_name'} .
									($param{'custom_delta'} ? " / s " : "") 
										.  " last " . $param{'time_span'},
				},
				use_delta		=> $param{'custom_delta'},
			},
		);

		my $x_tick_factor = $param{'width'} / 300;
		my %time_span_graph_parameters  = (
			minute	=> {
				x_label		=> 'Time',
				x_tick_number	=> 4 * $x_tick_factor, # need to be set to make x_number_format work
				x_number_format	=> sub { return strftime("%H:%M:%S", localtime($_[0])); },
			},
			hour	=> {
				x_label			=> 'Time',
				x_tick_number	=> 6 * $x_tick_factor, # need to be set to make x_number_format work
				x_number_format	=> sub { return strftime("%H:%M", localtime($_[0])); },
			},
			day	=> {
				x_label			=> 'Time',
				x_tick_number	=> 6 * $x_tick_factor, # need to be set to make x_number_format work
				x_number_format	=> sub { return strftime("%H:%M", localtime($_[0])); },
			},
			week	=> {
				x_label			=> 'Time',
				x_tick_number	=> 7 * $x_tick_factor, # need to be set to make x_number_format work
				x_number_format	=> sub { return strftime("%d.%m", localtime($_[0])); },
			},
			month	=> {
				x_label			=> 'Time',
				x_tick_number	=> 4, # need to be set to make x_number_format work
			x_number_format	=> sub { return strftime("%d.%m", localtime($_[0])); },
			},
		);
	
		if ( !$graph_info{$param{'type'}} 
			 || !$time_span_graph_parameters{$param{'time_span'}}) {
			return;
		}
	
		if ($param{'type'} eq 'custom') {
			if ($param{'custom_divisors'}) {
				my @divisors = split(/,\s*/, $param{'custom_divisors'});
				$graph_info{'custom'}->{'divisors'} = \@divisors;
			}
			if ($param{'custom_dividends'}) {
				my @dividends = split(/,\s*/, $param{'custom_dividends'});
				$graph_info{'custom'}->{'dividends'} = \@dividends;
			}
		}
		my ($data_ref, $x_min_value, $x_max_value) = Varnish::Statistics->generate_graph_data(
			$param{'unit_id'}, 
			$param{'is_node'},
			$param{'time_span'}, 
			$graph_info{$param{'type'}}->{'divisors'},
			$graph_info{$param{'type'}}->{'dividends'},
			$graph_info{$param{'type'}}->{'use_delta'}, 
			$param{'width'}
		);
		return if (!$data_ref);
	
		my $graph = GD::Graph::lines->new($param{'width'}, $param{'height'});
		my $title_font = gdSmallFont;
		my $axis_font = gdTinyFont;
		my $label_font = gdSmallFont;
		if ($param{'width'} > 300) {
			$title_font = gdGiantFont;
			$axis_font = gdSmallFont;
			$label_font = gdLargeFont;
		}
		$graph->set_title_font($title_font);
		$graph->set_legend_font($title_font);
		$graph->set_x_label_font($label_font);
		$graph->set_y_label_font($label_font);
		$graph->set_x_axis_font($axis_font);
		$graph->set_y_axis_font($axis_font);
		$graph->set((%{$graph_info{$param{'type'}}->{'graph_parameter'}}, 
				%{$time_span_graph_parameters{$param{'time_span'}}}),
				dclrs => ["#990200"],
				x_min_value => $x_min_value, x_max_value => $x_max_value,
				skip_undef => 1);

		my $graph_image = $graph->plot($data_ref);
		return if (!$graph_image);

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

		my $nodes_ref = Varnish::NodeManager->get_nodes();
		if ($nodes_ref && @$nodes_ref > 0) {
			my $node_id = $param{'node_id'} ? $param{'node_id'} : $nodes_ref->[0]->get_id();
			for my $node (@$nodes_ref) {
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
				foreground	=> '#00ff00',
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
