#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use DBI;
use Log::Minimal;
use PrettyFS::Monitor;
use opts;
use PrettyFS::ConfigLoader;

opts my $interval => {default => 1},
     my $config => { default => 'config.pl' },
     ;

my $conf = PrettyFS::ConfigLoader->load($config);
my $db_conf = $conf->{DB} or die "missing configuration for DB";
my $dbh = DBI->connect(@$db_conf) or die "Cannot connect to database: " . $DBI::errstr;

PrettyFS::Monitor->new(dbh => $dbh, interval => $interval)->run;

