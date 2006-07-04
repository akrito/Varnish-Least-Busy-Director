#!/usr/local/bin/perl -w
#
# $Id$
#

use strict;
use CGI;

my $q = new CGI;

my $foo = int($q->param('foo'));
my $i = ($foo * 2) % 5000;
my $j = ($foo * 2 + 1) % 5000;

print $q->header(-expires=>'+60m');

print "<h1>Page $foo</h1>\n";
print "<p><a href=\"/cgi-bin/recursor.pl?foo=$i\">Link $i</a></p>\n";
print "<p><a href=\"/cgi-bin/recursor.pl?foo=$j\">Link $j</a></p>\n";
