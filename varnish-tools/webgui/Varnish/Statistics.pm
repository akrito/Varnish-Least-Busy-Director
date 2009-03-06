package Varnish::Statistics;

use strict;
use POSIX qw(strftime);
use List::Util qw(first);

use Varnish::Util;
use Varnish::NodeManager;
use Varnish::DB;

{
	my $last_measure_time;
	my $clean_up_time;

	sub BEGIN {
		my $now = time();
		my ($sec, $min, $hour) = localtime($now);
		$clean_up_time = $now 
						+ (23 - $hour) *  3600
						+ (59 - $min) * 60
						+ (60 - $sec);
	}

	sub collect_data {
		my $time_stamp = time();
		my $nodes_ref = Varnish::NodeManager->get_nodes();

		if ($time_stamp > $clean_up_time) {
			Varnish::DB->clean_up();
			$clean_up_time += 86400;
		}

		for my $node (@$nodes_ref) {
			my $management = $node->get_management();
			my $stat_ref = {};
			if ($management) {
			 	$stat_ref = $management->get_stats();
			}
			Varnish::DB->add_stat($node, $stat_ref, $time_stamp);
		}
		$last_measure_time = $time_stamp;
	}


	sub get_last_measure {
		my ($self, $unit) = @_;

		my $stat_data_ref = Varnish::DB->get_stat_data($unit, $last_measure_time - 1);
		if ($stat_data_ref) {
			delete $stat_data_ref->[0]->{'has_data'};

			return ($last_measure_time, $stat_data_ref->[0]);
		}
		else {
			return (undef, undef);
		}
	}

	sub _union {
		my %temp_hash = map { $_ => 1 } @_;

		return keys %temp_hash;
	}
	
	sub generate_graph_data {
		my ($self, $unit_id, $is_node, $time_span, $divisors_ref, $dividends_ref, $use_delta, $desired_number_of_values) = @_;
		$desired_number_of_values ||= 0;
		
		my %seconds_for = (
			minute	=> 60,
			quarter	=> 900,
			hour	=> 3600,
			day		=> 86400,
			week	=> 604800,	
			month	=> 18144000, # 30 days
		);
		my $current_time = time();
		my $start_time = $current_time - $seconds_for{$time_span};
		my $poll_interval = get_config_value('poll_interval');
		if ($use_delta) {
			$start_time -= $poll_interval;
		}

		my @divisors = ($divisors_ref ? 
							map {  get_db_friendly_name($_); } @$divisors_ref : ());
		my @dividends = ($dividends_ref ? 
							map {  get_db_friendly_name($_); } @$dividends_ref : ());
		my @all_fields = _union(@dividends, @divisors);
	
		my $measures_ref;
		if ($is_node) {
			my $node = Varnish::NodeManager->get_node($unit_id);
			return ([],[], -1, -1) if (!$node);
			$measures_ref = Varnish::DB->get_stat_data($node, $start_time, \@all_fields);
		}
		else {
			my $group = Varnish::NodeManager->get_group($unit_id);
			return ([],[], -1, -1) if (!$group);
			$measures_ref = Varnish::DB->get_stat_data($group, $start_time, \@all_fields);
		}


		my @values;
		my @times;
		my $value2;
		my $last_value;
		my $last_divisor;
		my $last_dividend;
		my $last_total_requests;
		my $last_time;
		my $x_min;
		my $x_max;
		GENERATE_DATA:
		for my $measure_ref (@$measures_ref) {
			my $value;
			my $time = $measure_ref->{'time'};

			if ($measure_ref->{'has_data'}) {
				my $divisor_value = 0;
				my $dividend_value = 0;

				if (@divisors > 0) {
					for my $divisor (@divisors) {
						$divisor_value += $measure_ref->{$divisor};
					}
				}
				else {
					$divisor_value = 1;
				}
				if (@dividends) {
					for my $dividend (@dividends) {
						$dividend_value += $measure_ref->{$dividend};
					}
				}
				else {
					$dividend_value = 1;
				}
				if ($dividend_value) {
					$value = $divisor_value / $dividend_value;
				}

				if ($use_delta) {
					if (!defined($last_value)) {
						$last_value = $value;
						$last_dividend = $dividend_value;
						$last_divisor = $divisor_value;
						$last_time = $time;
						$last_total_requests = $measure_ref->{'total_requests'};
						next GENERATE_DATA;
					}
					my $delta_time = $time - $last_time;
					my $delta_value;
					if ($use_delta == 2) {
						if ($dividend_value != $last_dividend) {
							$delta_value = 
								($divisor_value - $last_divisor) / ($dividend_value - $last_dividend);
						}
						else {
							$delta_value = undef;
						}
					}
					else {
						if ($delta_time > 0) {
							$delta_value = ($value - $last_value) / $delta_time;
						}
						else {
							$delta_value = undef;
						}
					}

					$last_value = $value;
					# check if node has been restarted, as the delta would be huge
					# and negative if it has
					my $total_requests = $measure_ref->{'total_requests'};
					if ($total_requests < $last_total_requests) {
						$value = undef;
					}
					else {
						$value = $delta_value;
					}

					$last_dividend = $dividend_value;
					$last_divisor = $divisor_value;
					$last_total_requests = $total_requests;
					$last_time = $time;
				}
			}
			
			$x_min ||= $time;
			$x_max = $time;

			push @times, $time;
			push @values, $value;
		}
		
		my $possible_number_of_values = $seconds_for{$time_span} / $poll_interval;
		if ($desired_number_of_values && 
				$possible_number_of_values > $desired_number_of_values) {
			my $partition_size = $seconds_for{$time_span} / $desired_number_of_values;
			my $start_time = shift @times;
			my $aggregated_value = shift @values;
			my $aggregated_width = (defined($aggregated_value) ? 1 : 0);
			my $end_time = $start_time + $partition_size;
			my @new_times;
			my @new_values;
			
			while (my $time = shift(@times)) {
				my $value = shift @values;
				if ($time < $end_time) {
					if (defined($value)) {
						$aggregated_value += $value;
						$aggregated_width++;
					}
				}
				else {
					push @new_times, $start_time;
					if ($aggregated_width > 0) {
						push @new_values, $aggregated_value / $aggregated_width;
					}
					else {
						push @new_values, undef;
					}
					$start_time = $time;
					$end_time = $start_time + $partition_size;
					$aggregated_value = $value;
					$aggregated_width = (defined($value) ? 1 : 0);
				}
			}
			
			push @new_times, $start_time;
			if ($aggregated_width > 0) {
				push @new_values, $aggregated_value / $aggregated_width;
			}
			else {
				push @new_values, undef;
			}

			@times = @new_times;
			@values = @new_values;
		}

		unshift @times, $start_time;
		unshift @values, undef;

		return ([\@times, \@values], $x_min, $x_max);
	}
}

1;
