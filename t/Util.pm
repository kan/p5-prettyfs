package t::Util;
use strict;
use warnings;
use utf8;
use parent qw/Exporter/;
use DBI;
use PrettyFS::Client;

our @EXPORT = qw/get_dbh get_client/;

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

1;

