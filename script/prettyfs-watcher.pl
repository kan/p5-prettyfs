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
use Jonk::Client;

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
my $sth = $dbh->prepare(q{SELECT host, port, status FROM storage});
my $furl = Furl::HTTP->new(timeout => $timeout);
my $client = PrettyFS::Client->new(dbh => $dbh);

while (1) {
    $sth->execute();
    while (my ($host, $port, $status) = $sth->fetchrow_array()) {
        infof("request to $host:$port($status)");
        if (ping($host, $port)) {
            infof("$host:$port is alive");
            # alive
            if ($status == STORAGE_STATUS_DEAD) {
                $client->edit_storage_status(host => $host, port => $port, status => STORAGE_STATUS_ALIVE);
            }
        } else {
            infof("$host:$port is dead");
            if ($status == STORAGE_STATUS_ALIVE) {
                $client->edit_storage_status(host => $host, port => $port, status => STORAGE_STATUS_DEAD);
            }
        }
    }

    sleep $interval;
}

sub ping {
    my ($host, $port) = @_;

    try {
        my ($minor_version, $code, $msg, $headers, $body) = $furl->request(method => 'GET', host => $host, port => $port, path => '/?alive');
        return $code == 200 ? 1 : 0;
    } catch {
        warnf("error: $_");
        return 0;
    };
}

