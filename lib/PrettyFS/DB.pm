use strict;
use warnings;
use utf8;

package PrettyFS::DB;
use Class::Accessor::Lite (
    new => 1,
    ro  => [qw/dbh/],
);

sub search {
    my ( $self, $stmt, @binds ) = @_;
    my $x = $self->dbh->selectall_arrayref( $stmt, +{ Slice => +{} }, @binds );
    return wantarray ? @$x : $x;
}

sub single {
    my ( $self, $stmt, @binds ) = @_;
    return $self->dbh->selectrow_hashref( $stmt, +{}, @binds );
}

sub do {
    my ( $self, $stmt, @binds ) = @_;
    return $self->dbh->do($stmt, +{}, @binds);
}

1;

