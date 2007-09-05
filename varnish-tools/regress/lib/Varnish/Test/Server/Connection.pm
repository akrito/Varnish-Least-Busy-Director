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

Varnish::Test::Server::Connection

=head1 DESCRIPTION

An Varnish::Test::Server::Connection object is used to handle an
individual HTTP connection which stems from the listening socket
handled by L<Varnish::Test::Server>.

=cut

package Varnish::Test::Server::Connection;

use strict;
use HTTP::Request;
use HTTP::Status;

=head2 new

Called by a Server object when a new connection (given by the
file-handle argument) is established. This object is set as the
IO::Multiplex call-back object for this connection.

=cut

sub new($$) {
    my ($this, $server, $fh) = @_;
    my $class = ref($this) || $this;

    my $self = bless({ 'server' => $server,
		       'engine' => $server->{'engine'},
		       'fh' => $fh,
		       'mux' => $server->{'mux'},
		       'data' => '' }, $class);
    $self->{'mux'}->set_callback_object($self, $fh);
    return $self;
}

=head2 send_response

Called by test-cases to send a given HTTP::Response object out on the
associated HTTP connection.

=cut

sub send_response($$) {
    my ($self, $response) = @_;

    $response->message(status_message($response->code()))
	unless $response->message();
    $self->{'mux'}->write($self->{'fh'}, $response->as_string("\r\n"));
    $self->{'server'}->{'responses'} += 1;
    $self->{'server'}->logf("%s %s", $response->code(), $response->message());
}

=head2 shutdown

Called by test-cases to close HTTP connection.

=cut

sub shutdown($) {
    my ($self) = @_;

    my $inbuffer = $self->{'mux'}->inbuffer($self->{'fh'});

    if (defined($inbuffer) and $inbuffer ne '') {
	use Data::Dumper;

	$self->{'server'}->log('Junk or incomplete request. Discarding: ' . Dumper(\$inbuffer));
	$self->{'mux'}->inbuffer($self->{'fh'}, '');
    }

    $self->{'mux'}->close($self->{'fh'});
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
    # chance to parse it next time we get more data ("mux_input").
    while ($$data =~ /\n\r?\n/) {
	# If we find a double (CR)LF in the input data, we have at
	# least a complete header section of a message, so look for
	# content-length and decide what to do.

	my $request = HTTP::Request->parse($$data);
	my $content_ref = $request->content_ref;
	my $content_length = $request->content_length;

	if (defined($content_length)) {
	    my $data_length = length($$content_ref);
	    if ($data_length == $content_length) {
		# We found exactly content-length amount of data, so
		# empty input buffer and send request to event
		# handling.
		$$data = '';
		$self->{'server'}->got_request($self, $request);
	    }
	    elsif ($data_length < $content_length) {
		# We only received the first part of an HTTP message,
		# so break out of loop and wait for more.
		$mux->set_timeout($fh, 2);
		last;
	    }
	    else {
		# We have more than content-length data, which means
		# more than just one HTTP message. The extra data
		# (beyond content-length) is now at the end of
		# $$content_ref, so move it back to the input buffer
		# so we can parse it on the next iteration. Note that
		# this "substr" also removes this data from
		# $$content_ref (the message body of $request itself).
		$$data = substr($$content_ref, $content_length,
				$data_length - $content_length, '');
		# Send request to event handling.
		$self->{'server'}->got_request($self, $request);
	    }
	}
	else {
	    # HTTP requests without a content-length has no body by
	    # definition, so whatever was parsed as content must be
	    # the start of another request. Hence, move this back to
	    # input buffer and empty the body of this $request. Then,
	    # send $request to event handling.

	    $$data = $$content_ref;
	    $$content_ref = '';
	    $self->{'server'}->got_request($self, $request);
	}
    }
}

=head2 mux_timeout

Called by L<IO::Multiplex> when a specified timeout has been reached
on an associated file-handle.

=cut

sub mux_timeout($$$) {
    my ($self, $mux, $fh) = @_;

    $self->{'mux'}->set_timeout($fh, undef);
    $self->{'engine'}->ev_server_timeout($self);
}

=head2 mux_eof

Called by L<IO::Multiplex> when connection is being shutdown by
foreign host.

=cut

sub mux_eof($$$$) {
    my ($self, $mux, $fh, $data) = @_;

    # On server side, HTTP does not use EOF from client to signal end
    # of request, so if there is anything left in input buffer, it
    # must be incomplete because "mux_input" left it there.

    if ($$data ne '') {
	use Data::Dumper;

	$self->{'server'}->log('Junk or incomplete request. Discarding: ' . Dumper($data));
	$$data = '';
    }
}

1;

=head1 SEE ALSO

L<Varnish::Test::Server>
L<HTTP::Request>
L<HTTP::Response>
L<HTTP::Status>

=cut
