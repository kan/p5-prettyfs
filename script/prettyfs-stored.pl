#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use PrettyFS::Server::Store;
use Plack::Loader;
use opts;
use PrettyFS::DiskUsage;
use Proc::Guard;
use Log::Minimal;
use Config;

opts my $port => {default => 1919},
     my $base => {isa => 'Str', required =>1};

my $app = PrettyFS::Server::Store->new(base => $base)->to_app();

infof("Parent process: $$");

my $disk_usage = Proc::Guard->new(
    code => sub {
        infof("Disk Usage worker: $$");
        $0 = "prettyfs [disk-usage]";
        PrettyFS::DiskUsage->new(docroot => $base)->run();
    }
);

my %signo;
do {
    defined $Config{sig_name} || die "No sigs?";
    my $i;
    for my $name (split(' ', $Config{sig_name})) {
        $signo{$name} = $i;
        $i++;
    }
};
$SIG{TERM} = $SIG{INT} = sub {
    undef $disk_usage;

    exit $signo{$_[0]} + 128;
};
infof "access to http://localhost:$port/\n";
Plack::Loader->load('Twiggy', port => $port)->run($app);

