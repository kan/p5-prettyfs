package t::Util;
use strict;
use warnings;
use utf8;
use parent qw/Exporter/;
use DBI;
use PrettyFS::Client;
use Test::TCP 1.08;
use File::Temp qw/tempdir tmpnam/;
use Plack::Loader;
use Fcntl ':seek';
use PrettyFS::Server::Store;
use Log::Minimal;
use Module::Load;

our @EXPORT = qw/get_dbh get_client create_storage make_tmpfile ddf run_workers/;

sub get_dbh {
    my $dsn = shift || 'dbi:SQLite:';
    my $dbh = DBI->connect($dsn, '', '', {RaiseError => 1}) or die DBI->errstr;
    open my $fh, '<', 'sql/sqlite.sql' or die $!;
    $dbh->do($_) for grep /\S/, split /;/, do { local $/; <$fh>};
    return $dbh;
}

sub get_client {
    my $dbh = get_dbh();
    PrettyFS::Client->new(dbh => $dbh);
}

sub create_storage {
    return Test::TCP->new(
        code => sub {
            my $port = shift;
            my $app = PrettyFS::Server::Store->new(base => tempdir())->to_app;
            Plack::Loader->load('Twiggy', port => $port)->run($app);
        },
    );
}

sub make_tmpfile {
    my $content = shift;
    my $tmp = File::Temp->new();
    print {$tmp} $content;
    seek $tmp, 0, SEEK_SET;
    return $tmp;
}

use Jonk::Worker;
sub run_workers {
    my $dbh = shift;
    Carp::croak "missing dbh" unless $dbh;
    my @workers = qw/PrettyFS::Worker::Reaper PrettyFS::Worker::Replication PrettyFS::Worker::Deleter/;
    Module::Load::load($_) for @workers;

    my $fetcher = Jonk::Worker->new($dbh, {functions => \@workers});
    my %workers = map { $_ => $_->new(dbh => $dbh) } @workers;
    while (my $job = $fetcher->dequeue()) {
        debugf("run $job");
        my $worker = $workers{$job->{func}};
        $worker->run($job->{arg});
    }
}

1;

