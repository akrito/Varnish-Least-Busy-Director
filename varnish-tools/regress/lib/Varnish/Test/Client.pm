#!/usr/bin/perl -w
#-
# Copyright (c) 2006-2007 Linpro AS
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer
#    in this position and unchanged.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $Id$
#

=head1 NAME

Varnish::Test::Client - HTTP-client emulator

=head1 DESCRIPTION

Varnish::Test::Client objects have the capability of establishing HTTP
connections, sending requests and receiving responses.

=cut

package Varnish::Test::Client;

use strict;

use IO::Socket::INET;
use HTTP::Response;

our $id_seq = 1;

=head2 new

Called by test-cases to create a new Client object to be used to send
HTTP-requests.

=cut

sub new($$) {
    my ($this, $engine, $attrs) = @_;
    my $class = ref($this) || $this;

    my $self = bless({ 'engine' => $engine,
		       'mux' => $engine->{'mux'},
		       'id' => $id_seq++,
		       'requests' => 0,
		       'responses' => 0 }, $class);

    push(@{$self->{'engine'}->{'clients'}}, $self);

    return $self;
}

=head2 log

Logging facility.

=cut

sub log($$;$) {
    my ($self, $str, $extra_prefix) = @_;

    $self->{'engine'}->log($self, sprintf('CLI[%d]: ', $self->{'id'}) . ($extra_prefix || ''), $str);
}

=head2 logf

Logging facility using a formatting string as first argument.

=cut

sub logf($$;@) {
    my ($self, $fmt, @args) = @_;

    $self->{'engine'}->log($self, sprintf('CLI[%d]: ', $self->{'id'}), sprintf($fmt, @args));
}

=head2 send_request

Called by test-cases to send HTTP requests out on a connection.

=cut

sub send_request($$;$) {
    my ($self, $request, $timeout) = @_;

    if (!defined($self->{'fh'})) {
	my $fh = IO::Socket::INET->new('Proto'    => 'tcp',
				       'PeerAddr' => 'localhost',
				       'PeerPort' => '8080')
	    or die "socket(): $!\n";
	$self->{'fh'} = $fh;
	$self->{'mux'}->add($fh);
	$self->{'mux'}->set_callback_object($self, $fh);
    }
    $self->{'timeout'} = $timeout;
    $self->{'mux'}->set_timeout($self->{'fh'}, $timeout);
    $self->{'mux'}->write($self->{'fh'}, $request->as_string("\r\n"));
    $self->{'requests'} += 1;
    $self->logf("%s %s %s", $request->method(), $request->uri(), $request->protocol());
}

=head2 got_response

Called by mux_input and mux_eof to dispatch event related to received
HTTP response.

=cut

sub got_response($$) {
    my ($self, $response) = @_;

    $self->{'responses'} += 1;
    $self->logf("%s %s", $response->code(), $response->message());
    $self->{'engine'}->ev_client_response($self, $response);
}

=head2 shutdown

Called by test-cases to shutdown client including termination of HTTP
connection.

=cut

sub shutdown($) {
    my ($self) = @_;

    if (defined($self->{'fh'})) {
	my $inbuffer = $self->{'mux'}->inbuffer($self->{'fh'});

	if (defined($inbuffer) and $inbuffer ne '') {
	    use Data::Dumper;

	    $self->log('Discarding: ' . Dumper(\$inbuffer));
	    $self->{'mux'}->inbuffer($self->{'fh'}, '');
	}

	$self->{'mux'}->close($self->{'fh'});
	$self->{'fh'} = undef;
    }
}

=head1 IO::MULTIPLEX CALLBACKS

=head2 mux_input

Called by L<IO::Multiplex> when new input is received on an associated
file-handle. Complete HTTP messages are extracted from the input
buffer, while any incomplete message is left in the buffer, awaiting
more input (mux_input) or EOF (mux_eof).

=cut

sub mux_input($$$$) {
    my ($self, $mux, $fh, $data) = @_;

    $mux->set_timeout($fh, undef);

    # Iterate through the input buffer ($$data) and identify HTTP
    # messages, one per iteration. Break out of the loop when there
    # are no complete HTTP messages left in the buffer, and let
    # whatever data remains stay in the buffer, as we will get a new
    # chance to parse it next time we get more data ("mux_input") or
    # if connection is closed ("mux_eof").

    while ($$data =~ /\n\r?\n/) {
	# If we find a double (CR)LF in the input data, we have at
	# least a complete header section of a message, so look for
	# content-length and decide what to do.

	my $response = HTTP::Response->parse($$data);
	my $content_length = $response->content_length;

	if (defined($content_length)) {
	    my $content_ref = $response->content_ref;
	    my $data_length = length($$content_ref);
	    if ($data_length == $content_length) {
		# We found exactly content-length amount of data, so
		# empty input buffer and send response to event
		# handling.
		$$data = '';
		$self->got_response($response);
	    }
	    elsif ($data_length == 0) {
		# We got a body-less response, which may or may not
		# be correct; leave it to the test case to decide.
		$self->log("No body received despite" .
			   " Content-Length $content_length");
		$$data = '';
		$self->got_response($response);
	    }
	    elsif ($data_length < $content_length) {
		# We only received the first part of an HTTP message,
		# so break out of loop and wait for more.
		$self->log("Partial body received" .
			   " ($data_length of $content_length bytes)");
		$mux->set_timeout($fh, $self->{'timeout'});
		last;
	    }
	    else {
		# We have more than content-length data, which means
		# more than just one HTTP message. The extra data
		# (beyond content-length) is now at the end of
		# $$content_ref, so move it back to the input buffer
		# so we can parse it on the next iteration. Note that
		# this "substr" also removes this data from
		# $$content_ref (the message body of $response
		# itself).
		$$data = substr($$content_ref, $content_length,
				$data_length - $content_length, '');

		# Send response to event handling.
		$self->got_response($response);
	    }
	}
	else {
	    # There is no content-length among the headers, so break
	    # out of loop and wait for EOF, in which case mux_eof will
	    # reparse the input buffer as a HTTP message and send it
	    # to event handling from there.
	    $self->log("Partial response. Content-Length unknown." .
		       " Expecting CLOSE as end-of-response.");
	    $mux->set_timeout($fh, $self->{'timeout'});
	    last;
	}
    }

    # At this point, what remains in the input buffer is either
    # nothing at all or a partial HTTP message.
}

=head2 mux_eof

Called by L<IO::Multiplex> when connection is being shutdown by
foreign host.

=cut

sub mux_eof($$$$) {
    my ($self, $mux, $fh, $data) = @_;

    if ($$data ne '') {
	die "Junk or incomplete response\n"
	    unless $$data =~ "\n\r?\n";

	my $response = HTTP::Response->parse($$data);
	$$data = '';
	$self->got_response($response);
    }
}

=head2 mux_timeout

Called by L<IO::Multiplex> when a specified timeout has been reached
on an associated file-handle.

=cut

sub mux_timeout($$$) {
    my ($self, $mux, $fh) = @_;

    $self->{'mux'}->set_timeout($fh, undef);
    $self->{'engine'}->ev_client_timeout($self);
}

=head2 mux_close

Called by L<IO::Multiplex> when an associated file-handle has been
closed.

=cut

sub mux_close($$) {
    my ($self, $mux, $fh) = @_;

    $self->{'fh'} = undef;
}

1;

=head1 SEE ALSO

L<HTTP::Response>
L<HTTP::Request>

=cut
