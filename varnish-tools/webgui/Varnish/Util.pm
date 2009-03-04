package Varnish::Util;

use strict;
use Exporter;
use base qw(Exporter);
use POSIX qw(strftime);
use URI::Escape;
use Algorithm::Diff;

our @EXPORT = qw(
				read_config
				set_config
				print_config
				get_config_value
				read_file
				get_formatted_percentage
				get_formatted_bytes
				get_db_friendly_name 
				get_error
				set_error
				no_error
				log_info
				log_error
				url_encode
				url_decode
				diff
				);

{
	my %config;
	my $error;
	my $log_handle;

	sub read_config {
		my ($filename) = @_;

		my $handle;
		if (!open($handle, "<$filename")) {
			die "Could not open config file $filename\n";
		}

		while (<$handle>) {
			if (/^(\w+)\s*=\s*(.*?)$/) {
				my $key = lc $1;
				my $value = $2;
				$config{$key} = $value;
			}
		}

		close($handle);	
	}

	sub set_config {
		my ($config_ref) = @_;
			
		my @keys = keys %$config_ref;
		for my $key (@keys) {
			$config{$key} = $config_ref->{$key};
		}

		if ($config{'log_filename'}) {
			if (!open($log_handle, ">>" . $config{'log_filename'})) {
				die "Could not open log file " . $config{'log_filename'} . " for writing";
			}
			$log_handle->autoflush(1); # FIXME: Remove it, or is it usefull?
		}
	}

	sub print_config {
		print "Config:\n";
		while (my ($k, $v) = each(%config)) {
			print "$k: $v\n";
		}
	}

	sub get_config_value {
		my ($key) = @_;

		return $config{$key};
	}

	sub read_file($) {
		my ($filename) = @_;	

		open(my $fh, "<$filename" );
		my $content = do { local($/); <$fh> };
		close($fh);

		return $content;
	}

	sub get_formatted_percentage {
		my ($divisor, $dividend) = @_;
		
		return $dividend > 0 ? sprintf( "%.2f", 100 * ($divisor / $dividend)) : "inf";
	}

	# thanks to foxdie at #varnish for php snippet
	sub get_formatted_bytes {
		my ($bytes) = @_;
        
		if ($bytes > 1099511627776) {
			return sprintf( "%.3f TB", $bytes / 1099511627776);
        }
        elsif ($bytes > 1073741824) {
			return sprintf( "%.3f GB", $bytes / 1073741824);
        }
        elsif ($bytes > 1048576) {
			return sprintf( "%.3f MB", $bytes / 1048576);
        }
        elsif ($bytes > 1024) {
			return sprintf( "%.3f KB", $bytes / 1024);
        }
        else {
			return $bytes . " B";
        }
	}

	sub get_db_friendly_name {
		my ($name) = @_;

		$name =~ s/ /_/g;
		$name =~ s/\(/_/g;
		$name =~ s/\)/_/g;

		return lc($name);
	}


	sub set_error {
		my ($new_error) = @_;
		
		$error = $new_error;

		return;
	}

	sub get_error {
		
		return $error ? $error : '';
	}

	sub no_error {
		my ($return_value) = @_;

		$error = "";

		return defined($return_value) ? $return_value : 1;
	}

	sub _log {
		my ($severity, $string) = @_;

		return if (!$log_handle);

		my $time_stamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
		print $log_handle "[$time_stamp] [$severity] $string\n";
	}

	sub log_error {
		my ($string) = @_;

		_log("ERROR", $string);
	}

	sub log_info {
		my ($string) = @_;

		_log("INFO", $string);
	}

	sub url_decode {
		my ($value) = @_;

		$value = uri_unescape($value);
		$value =~ s/\+/ /g;

		return $value;
	}

	sub url_encode {
		my ($value) = @_;

		$value = uri_escape($value);
		$value =~ s/ /\+/g;

		return $value;
	}

	sub diff {
		my ($old_text, $new_text) = @_;
		
		my @old_text_lines = split /\n/, $old_text;
		my @new_text_lines = split /\n/, $new_text;
		my $diff_text = "";
		my $diff = Algorithm::Diff->new( \@old_text_lines, \@new_text_lines );
		$diff->Base( 1 );   # Return line numbers, not indices
		while ($diff->Next()) {
			next if  $diff->Same();
			my $sep = '';
			if (!$diff->Items(2)) {
				$diff_text .= sprintf("%d,%dd%d\n",
					 $diff->Get(qw( Min1 Max1 Max2 )));
			} elsif (!$diff->Items(1)) {
				$diff_text .= sprintf("%da%d,%d\n",
					$diff->Get(qw( Max1 Min2 Max2 )));
			} else {
				$sep = "---\n";
				$diff_text .= sprintf("%d,%dc%d,%d\n", 
					$diff->Get(qw( Min1 Max1 Min2 Max2 )));
			}
			$diff_text .= "< $_" for $diff->Items(1);
			$diff_text .= $sep;
			$diff_text .= "> $_" for $diff->Items(2);
		}

		return $diff_text;
	}
}

1;
