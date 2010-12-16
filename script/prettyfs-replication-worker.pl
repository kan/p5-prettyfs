#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Jonk::Worker;
use Parallel::Prefork;
use Getopt::Long;
use DBI;
use Log::Minimal;

my $interval = 1;
my $max_job_count = 100;
my $config_path = 'config.pl';
my $max_workers = 1;
GetOptions(
    'interval=i' => \$interval,
    'max_job_count=i' => \$max_job_count,
    'c|config=s' => \$config_path,
    'max_workers=i' => \$max_workers,
);

my $pm = Parallel::Prefork->new(
    {
        max_workers  => $max_workers,
        trap_signals => {
            TERM => 'TERM',
            HUP  => 'TERM',
            USR1 => undef,
        }
    }
);

die "missing configuration file: $config_path" unless -f $config_path;
my $config = do $config_path or die "cannot load configuration file: $config_path : $@";
my $db_conf = $config->{DB} or die "missing configugration: DB";

local $Log::Minimal::PRINT = sub {
    my ( $time, $type, $message, $trace) = @_;
    warn "$time [$$] [$type] $message at $trace\n";
};

while ( $pm->signal_received ne 'TERM' ) {
    $pm->start and next;

    my $dbh = DBI->connect(@$db_conf) or die "Cannot connect to database server: $DBI::errstr";
    my $worker = Jonk::Worker->new($dbh, {functions => ['PrettyFS::Worker::Replication']});
    my $job_count = $max_job_count;
    while ($job_count--) {
        if (my $job = $worker->dequeue) {
            my $uuid = $job->{arg} or die;
            infof("working: $uuid");
            try {
                PrettyFS::Worker::Replication->work($uuid);
                infof("working successfully: $uuid");
            } catch {
                critff("worker dies: $_");
            };
        } else {
            debugf("sleeping $interval secs");
            sleep $interval;
        }
    }

    $pm->finish;
}

$pm->wait_all_children();

