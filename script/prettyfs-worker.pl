#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Jonk::Worker;
use Parallel::Prefork;
use Getopt::Long;
use DBI;
use Log::Minimal;
use Module::Load ();
use Pod::Usage;
use Config;

my $interval = 1;
my $max_job_count = 100;
my $config_path = 'config.pl';
my @functions;
GetOptions(
    'interval=i' => \$interval,
    'max_job_count=i' => \$max_job_count,
    'c|config=s' => \$config_path,
    'worker=s@' => \@functions,
);
pod2usage() unless @functions;
@functions = map { "PrettyFS::Worker::$_" } @functions;
for (@functions) {
    Module::Load::load($_);
}

die "missing configuration file: $config_path" unless -f $config_path;
my $config = do $config_path or die "cannot load configuration file: $config_path : $@";
my $db_conf = $config->{DB} or die "missing configugration: DB";

local $Log::Minimal::PRINT = sub {
    my ( $time, $type, $message, $trace) = @_;
    warn "$time [$$] [$type] $message at $trace\n";
};

my %signo;
do {
    defined $Config{sig_name} || die "No sigs?";
    my $i;
    for my $name (split(' ', $Config{sig_name})) {
        $signo{$name} = $i;
        $i++;
    }
};
my %pid_map;
$SIG{TERM} = $SIG{INT} = sub {
    # kill all children
    kill keys %pid_map;
    1 while wait()!=-1;

    exit $signo{$_[0]} + 128;
};
for my $function (@functions) {
    run_child($function);
}

while (%pid_map) {
    if (my $pid = wait()) {
        my $function = delete $pid_map{$pid};
        run_child($function);
    }
}

sub run_child {
    my $function = shift;
    my $pid      = fork();
    die $! unless defined $pid;

    if ($pid) {
        $pid_map{$pid} = $function;
        return;
    }
    else {    # child
        my $dbh = DBI->connect(@$db_conf)
          or die "Cannot connect to database server: $DBI::errstr";

        my $fetcher = Jonk::Worker->new( $dbh, { functions => \@functions } );
        my $job_count = $max_job_count;
        my %worker_cache;
        my $worker = $function->new(dbh => $dbh);
        while ($job_count) {
            if ( my $job = $fetcher->dequeue ) {
                infof("running job");

                my $uuid = $job->{arg} or die;
                infof("working: $uuid");
                try {
                    $worker->work($uuid);
                    infof("working successfully: $uuid");
                }
                catch {
                    critf("worker dies: $_");
                };
                $job_count--;
            }
            else {
                debugf("sleeping $interval secs");
                sleep $interval;
            }
        }
        exit 0;
    }
}

__END__

=head1 SYNOPSIS

    % prettyfs-worker --worker Repilcation

