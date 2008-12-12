package Varnish::Util;

use strict;
use Exporter;
use base qw(Exporter);

our @EXPORT = qw(
				set_config
				get_config_value
				read_file
				get_formatted_percentage
				get_formatted_bytes
				);

{
	my %config;

	sub set_config {
		my ($config_ref) = @_;

		%config = %{$config_ref};
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
}

1;
