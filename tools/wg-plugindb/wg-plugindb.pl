#!/usr/bin/perl -w

use DB_File;
use Fcntl;
use strict;
use utf8;

my $plugin_infofile = "/tmp/wiregate_plugin.db";
my %plugin_info;
tie %plugin_info, "DB_File", $plugin_infofile, O_RDONLY, 0666, $DB_HASH
 or die "Cannot open file 'plugin_info': $!";

print "Content-Type: application/json; charset=utf-8\n\n";

print "{ ";
# Split query-string into name/value pairs
my @pairs = split(/&/, $ENV{'QUERY_STRING'});
my $sep ='';

foreach my $pair (@pairs)
{
    my ($name, $value) = split(/=/, $pair);
    if ($name eq "name" && defined($plugin_info{$value}) ) {
        print "$sep \"$value\" : \"$plugin_info{$value}\" ";
        $sep = ',';
    }
}

# end json
print " }";
