#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use PrettyFS::Client;
use Getopt::Long;
use DBI;
use Config::Tiny;
use Furl::HTTP;
use Log::Minimal;
use PrettyFS::Constants;

my $interval = 1;
my $config_file = 'config.pl';
my $timeout = 3;
GetOptions(
    'interval=i' => \$interval,
    'c|config=s'   => \$config_file,
    'timeout=i'    => \$timeout,
);
die "configuration file is not exists: $config_file" unless -f $config_file;
my $config = do $config_file or die "cannot load configuration file: $config_file: $@";
my $db_conf = $config->{DB} or die "missing configuration for DB";
my $dbh = DBI->connect(@$db_conf) or die "Cannot connect to database: " . $DBI::errstr;
my $sth = $dbh->prepare(q{SELECT host, port, status FROM storage}) or die $dbh->errstr;
my $furl = Furl::HTTP->new(timeout => $timeout);
my $client = PrettyFS::Client->new(dbh => $dbh);

while (1) {
    $sth->execute();
    while (my ($host, $port, $status) = $sth->fetchrow_array()) {
        infof("request to $host:$port($status)");
        $client->update_storage_status(host => $host, port => $port, current_status => $status);
    }

    sleep $interval;
}

