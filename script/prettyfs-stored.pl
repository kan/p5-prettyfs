#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use PrettyFS::Server::Store;
use Plack::Loader;
use opts;

opts my $port => {default => 1919},
     my $base => {isa => 'Str', required =>1};

my $app = PrettyFS::Server::Store->new(base => $base)->to_app();

print "access to http://localhost:$port/\n";
Plack::Loader->load('Twiggy', port => $port)->run($app);

