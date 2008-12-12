package Varnish::Statistics;

use strict;
use POSIX qw(strftime);
use List::Util qw(first);

use Varnish::Util;
use Varnish::NodeManager;

{
	my %data;
	my $last_measure_ref;
	my $last_measure_time;

	sub collect_data {
		my $time_stamp = time();
		my %measure;
		my $good_stat_ref;
		my @nodes = Varnish::NodeManager->get_nodes();

		my @bad_nodes;
		for my $node (@nodes) {
			my $management = $node->get_management();
			my $stat_ref;
			if ($management) {
			 	$stat_ref = $management->get_stats();
			}
			if ($stat_ref) {
				$measure{$node} = $stat_ref;
				if (!$good_stat_ref) {
					$good_stat_ref = $stat_ref;
				}
			}
			else {
				push @bad_nodes, $node;
			}
		}

		if (@bad_nodes && $good_stat_ref) {
			for my $bad_node (@bad_nodes) {
				$measure{$bad_node}->{'missing data'} = 1;
				for my $key (keys %$good_stat_ref) {
					$measure{$bad_node}->{$key} = -1;
				}
			}
		}

		$data{$time_stamp} = \%measure;
		$last_measure_ref = \%measure;
		$last_measure_time = $time_stamp;
	}


	sub get_last_measure {
	
		return ($last_measure_time, $last_measure_ref);
	}
	
	sub generate_graph_data {
		my ($self, $node_id, $time_span, $divisors_ref, $dividends_ref, $use_delta) = @_;
		
		my %seconds_for = (
			minute	=> 60,
			hour	=> 3600,
			day		=> 86400,
			week	=> 604800,	
			month	=> 18144000, # 30 days
		);
		my $start_time = time() - $seconds_for{$time_span};
		if ($use_delta) {
			$start_time -= get_config_value('poll_interval');
		}
		my $node = first { 
						$_->get_id() == $node_id
					} Varnish::NodeManager->get_nodes();

		my @measures = grep { 
							$_ > $start_time 
						} (sort keys %data);
		my @values;
		my $last_value;
		GENERATE_DATA:
		for my $measure (@measures) {
			my $value;
			if (!$data{$measure}->{$node}->{'missing data'}) {
				my $divisor_value = 0;
				my $dividend_value = 0;

				if ($divisors_ref && @$divisors_ref) {
					for my $divisor (@$divisors_ref) {
						$divisor_value += $data{$measure}->{$node}->{$divisor};
					}
				}
				else {
					$divisor_value = 1;
				}
				if ($dividends_ref && @$dividends_ref) {
					for my $dividend (@$dividends_ref) {
						$dividend_value += $data{$measure}->{$node}->{$dividend};
					}
				}
				else {
					$dividend_value = 1;
				}
				if ($dividend_value) {
					$value = $divisor_value / $dividend_value;
				}

				if ($use_delta) {
					if (!$last_value) {
						$last_value = $value;
						next GENERATE_DATA;
					}
					my $delta_value = $value - $last_value;
					$last_value = $value;
					# if the value is negative, then we have had restart and don't plot it.
					if ($delta_value < 0) {
						$value = undef;
					}
					else {
						$value = $delta_value;
					}
				}
			}
			push @values, $value;
		}

		return [ \@measures, \@values ];
	}
}

1;
