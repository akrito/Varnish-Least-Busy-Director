#!/usr/local/bin/perl -w
#
# $Id$
#

use strict;
use CGI;

my $q = new CGI;

my $foo = int($q->param('foo'));
my $i = ($foo * 2) % 100000;
my $j = ($foo * 2 + 1) % 100000;

my $exp = ($foo % 1500) + 300;	# 300 to 1800 seconds
print $q->header(-expires=>"+$exp");

print "<h1>Page $foo</h1>\r\n";
print "<p><a href=\"/cgi-bin/recursor.pl?foo=$i\">Link $i</a></p>\r\n";
print "<p><a href=\"/cgi-bin/recursor.pl?foo=$j\">Link $j</a></p>\r\n";
print "\r\n"x4096
