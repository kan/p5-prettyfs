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

infof "access to http://localhost:$port/\n";
Plack::Loader->load('Twiggy', port => $port)->run($app);

