package PrettyFS::Client;
use strict;
use warnings;
use utf8;
use Class::Accessor::Lite (
    new => 0,
    ro  => [qw/dbh ua jonk/],
);
use Carp ();
use PrettyFS::Constants;
use Furl::HTTP;
use Jonk::Client;
use List::Util qw/shuffle/;
use Params::Validate;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    Carp::croak("missing mandatory parameter: dbh") unless exists $args{dbh};
    my $self = bless {%args}, $class;
    $self->{ua} ||= Furl::HTTP->new();
    $self->{jonk} ||= Jonk::Client->new($self->dbh);
    return $self;
}

sub put_file {
    my ($self, $uuid, $fh, $size) = @_;
    $size = -s $fh unless defined $size;

    my @storage_nodes = shuffle @{$self->dbh->selectall_arrayref(q{SELECT * FROM storage WHERE status=?}, {Slice => {}}, STORAGE_STATUS_ALIVE)};
    for my $storage (@storage_nodes) {
        my ($minor_version, $code, $msg, $headers, $body) = $self->ua->request(
            method => 'PUT',
            path   => "/$uuid",
            host   => $storage->{host},
            port   => $storage->{port},
        );
        if ($code == 200) {
            $self->put_file_post_process($storage->{storage_id}, $uuid, $size);
            return 1;
        } elsif ($code == 500) {
            $self->edit_storage_status(host => $storage->{host}, port => $storage->{port}, status => STORAGE_STATUS_DEAD);
        }
    }
    Carp::croak "No storage server is available";
}

sub put_file_post_process {
    my ($self, $storage_id, $uuid, $size) = @_;

    $self->dbh->do(q{INSERT INTO file (file_uuid, storage_id, size) VALUES (?, ?, ?)}, {}, $uuid, $storage_id, $size) or Carp::croak("Cannot insert to database: " . $self->dbh->errstr);
    $self->jonk->insert(
        'PrettyFS::Worker::Replication',
        $uuid
    );
}

sub get_urls {
    my ($self, $uuid) = @_;

    my $sth = $self->dbh->prepare(q{SELECT storage.* FROM file INNER JOIN storage ON (file.storage_id=storage.storage_id) WHERE file_uuid=?}) or Carp::croak("Cannot prepare statement" . $self->dbh->errstr);
    $sth->execute($uuid);
    my @ret;
    while (my $row = $sth->fetchrow_hashref) {
        push @ret, "http://$row->{storage_host}:$row->{storage_port}/$uuid";
    }
    return wantarray ? @ret : \@ret;
}

sub edit_storage_status {
    my $self = shift;
    my $args = {validate(
        @_ => { host => 1, port => 1, status => 1}
    )};

    $self->dbh->do(q{UPDATE storage SET status=? WHERE host=? AND port=?}, {}, $args->{status}, $args->{host}, $args->{port}) == 1 or Carp::croak("cannot update storage information: " . $self->dbh->errstr);
}

sub add_storage {
    my $self = shift;
    my $args = {validate(
        @_ => { host => 1, port => 1}
    )};

    $self->dbh->do(q{INSERT INTO storage (host, port) VALUES (?, ?)},
                        {}, $args->{host}, $args->{port}) or Carp::croak "Cannot insert storage: $args->{host}, $args->{port}: " . $self->dbh->errstr;
}

sub list_storage {
    my $self = shift;

    my $rows = $self->dbh->selectall_arrayref(q{SELECT * FROM storage}, {Slice => {}}) or Carp::croak "Cannot select storage: " . $self->dbh->errstr;
    return wantarray ? @$rows : $rows;
}

sub delete_storage {
    my $self = shift;
    my $args = {validate(
        @_ => { host => 1, port => 1}
    )};

    $self->dbh->do(q{DELETE FROM storage WHERE host=? AND port=?},
                        {}, $args->{host}, $args->{port}) or Carp::croak "Cannot delete storage: $args->{host}, $args->{port}: " . $self->dbh->errstr;
}

1;

