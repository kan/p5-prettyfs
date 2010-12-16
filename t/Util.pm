package t::Util;
use strict;
use warnings;
use utf8;
use parent qw/Exporter/;
use DBI;

our @EXPORT = qw/get_dbh/;

sub get_dbh {
    my $dbh = DBI->connect("dbi:SQLite:", '', '', {RaiseError => 1}) or die DBI->errstr;
    open my $fh, '<', 'sql/sqlite.sql' or die $!;
    $dbh->do($_) for grep /\S/, split /;/, do { local $/; <$fh>};
    return $dbh;
}

1;

