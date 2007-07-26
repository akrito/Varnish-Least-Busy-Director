#!/usr/bin/perl -w
#-
# Copyright (c) 2007 Linpro AS
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

package Varnish::Test::Case::HTTPregexPurge;

use strict;
use base 'Varnish::Test::Case';

use Data::Dumper;

our $VCL = <<EOVCL;
sub vcl_recv {
	if (req.request == "REPURGE") {
		purge(req.url);
		error 404 "Purged";
	}
}
EOVCL

our $body_p = "Hello World! -> purge\n";
our $body_k = "Hello World! -> keep\n";

sub testPagePurged($) {
    my ($self) = @_;

    my $client = $self->new_client;
    #for (my $i = 0; $i < 2; $i++) {
	my $get_p_request = HTTP::Request->new('GET', '/purge');
	$get_p_request->protocol('HTTP/1.1');
	my $get_k_request = HTTP::Request->new('GET', '/keep');
	$get_k_request->protocol('HTTP/1.1');
	my $purge_request = HTTP::Request->new('REPURGE', '/purge');
        $purge_request->protocol('HTTP/1.1');
        
	
	# Fetch the two pages, so they'll get cached
	$client->send_request($get_p_request, 2);
	my ($event, $response) = $self->run_loop('ev_client_response', 'ev_client_timeout');
	die "Client time-out before receiving a (complete) response\n"
	    if $event eq 'ev_client_timeout';
	die "Empty body\n"
	    if $response->content eq '';

        $client->send_request($get_k_request, 2);
	my ($event, $response) = $self->run_loop('ev_client_response', 'ev_client_timeout');
	die "Client time-out before receiving a (complete) response\n"
	    if $event eq 'ev_client_timeout';
	die "Empty body\n"
	    if $response->content eq '';

        
        # Check that the purge page is cached
	$client->send_request($get_p_request, 2);
	($event, $response) = $self->run_loop('ev_client_response', 'ev_client_timeout');
	die "Client time-out before receiving a (complete) response\n"
	    if $event eq 'ev_client_timeout';
	die "Empty body\n"
	    if $response->content eq '';
	die "Not cached\n"
	    if $response->header('x-varnish') !~ /\d+ \d+/;
	    
		      
        # Purge the purge page
        $client->send_request($purge_request, 2);
        ($event, $response) = $self->run_loop('ev_client_response', 'ev_client_timeout');
        # For some reason it times out on the first attempt, so we have to run the
        # loop an extra time to get the response. Could this be a bug in the framework?
        ($event, $response) = $self->run_loop('ev_client_response', 'ev_client_timeout')
        	if $event eq 'ev_client_timeout';

	
	# Check that the purge page is no longer cached
	$client->send_request($get_p_request, 2);
	($event, $response) = $self->run_loop('ev_client_response', 'ev_client_timeout');
	die "Client time-out before receiving a (complete) response\n"
	    if $event eq 'ev_client_timeout';
	die "Empty body\n"
	    if $response->content eq '';
	die "Still Cached\n"
	    if $response->header('x-varnish') =~ /\d+ \d+/;
	
	
	# Check that the keep page is still cached
	$client->send_request($get_k_request, 2);
	($event, $response) = $self->run_loop('ev_client_response', 'ev_client_timeout');
	die "Client time-out before receiving a (complete) response\n"
	    if $event eq 'ev_client_timeout';
	die "Empty body\n"
	    if $response->content eq '';
	die "Still Cached\n"
	    if $response->header('x-varnish') !~ /\d+ \d+/;
	

    $client->shutdown();

    return 'OK';
}

sub ev_server_request($$$$) {
    my ($self, $server, $connection, $request) = @_;
    my $body = "";

    # Return the right content
    if ($request->uri =~ /purge/) {
      $body = $body_p;
    }
    elsif ($request->uri =~ /keep/) {
      $body = $body_k;
    }

    my $response = HTTP::Response->new(200, undef,
				       [ 'Content-Length', length($body),
					 'Connection', 'Keep-Alive' ],
				       $body);
    $response->protocol('HTTP/1.1');
    $connection->send_response($response);
}

1;
