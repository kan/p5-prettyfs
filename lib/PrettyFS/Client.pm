package PrettyFS::Client;
use strict;
use warnings FATAL => 'all';
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
use Sub::Args 0.04;
use Try::Tiny;
use Data::UUID;

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
    my $self = shift;
    my $args = args({fh => 1, bucket => 0, ext => 0}, @_);
    my $size = -s $args->{fh};

    (my $uuid = Data::UUID->new->create_b64()) =~ s/=//g;

    my $path;
    my $bucket_id='';
    if ($args->{bucket}) {
        my $bucket = $self->dbh->selectrow_hashref(q{SELECT * FROM bucket WHERE name=?}, {}, $args->{bucket});
        unless ($bucket) {
            Carp::croak "unknown bucket: $args->{bucket}";
        }
        $bucket_id = $bucket->{id};
        $path = "/$bucket->{name}/$uuid";
    } else {
        $path = "/$uuid";
    }

    $path .= ".$args->{ext}" if $args->{ext};


    my @storage_nodes = shuffle @{$self->dbh->selectall_arrayref(q{SELECT * FROM storage WHERE status=?}, {Slice => {}}, STORAGE_STATUS_ALIVE)};
    for my $storage (@storage_nodes) {
        my ( $minor_version, $code, $msg, $headers, $body ) =
          $self->ua->request(
            method     => 'PUT',
            path_query => $path,
            host       => $storage->{host},
            port       => $storage->{port},
            content    => $args->{fh},
          );
        if ($code == 200) {
            $self->put_file_post_process($storage->{id}, $bucket_id, $uuid, $size, $args->{ext});
            return $uuid;
        } elsif ($code == 500) {
            $self->edit_storage_status(host => $storage->{host}, port => $storage->{port}, status => STORAGE_STATUS_DEAD);
        }
    }
    Carp::croak "No storage server is available";
}

sub put_file_post_process {
    my ($self, $storage_id, $bucket_id, $uuid, $size, $ext) = @_;

    $self->dbh->do(q{INSERT INTO file (uuid, storage_id, bucket_id, size, ext) VALUES (?, ?, ?, ?, ?)}, {}, $uuid, $storage_id, $bucket_id, $size, $ext)
        or Carp::croak("Cannot insert to database: " . $self->dbh->errstr);
    $self->jonk->enqueue(
        'PrettyFS::Worker::Replication',
        $uuid
    );
}

sub delete_file {
    my ($self, $uuid) = @_;

    # mark delete
    $self->dbh->do(q{UPDATE file SET del_fg=1 WHERE uuid=?}, {}, $uuid)
        or Carp::croak("Cannot update to database: " . $self->dbh->errstr);

    $self->jonk->enqueue(
        'PrettyFS::Worker::Deleter',
        $uuid
    );
}

sub get_urls {
    my ($self, $uuid) = @_;

    my $file = $self->dbh->selectrow_hashref(q{SELECT * FROM file WHERE uuid=?}, {}, $uuid);# or Carp::croak "Cannot select file: $uuid" . $self->dbh->errstr;
    unless ($file) {
        return;
    }

    my $bucket;
    if ($file->{bucket_id}) {
        $bucket = $self->dbh->selectrow_hashref(q{SELECT * FROM bucket WHERE id=?}, {}, $file->{bucket_id}) or Carp::croak "Cannot select bucket: $file->{bucket_id}" . $self->dbh->errstr;
        unless ($bucket) {
            Carp::croak "unknown bucket: $bucket";
        }
    }

    my $sth = $self->dbh->prepare(q{SELECT storage.* FROM file INNER JOIN storage ON (file.storage_id=storage.id) WHERE file.uuid=?}) or Carp::croak("Cannot prepare statement" . $self->dbh->errstr);
    $sth->execute($uuid);
    my @ret;
    while (my $row = $sth->fetchrow_hashref) {
        my $path  = "http://$row->{host}:$row->{port}";
           $path .= $bucket ? "/$bucket->{name}/$uuid" : "/$uuid";
           $path .= ".$file->{ext}" if $file->{ext};

        push @ret, $path;
    }
    return wantarray ? @ret : \@ret;
}

sub edit_storage_status {
    my $self = shift;
    my $args = args({host => 1, port => 1, status => 1}, @_);

    $self->dbh->do(q{UPDATE storage SET status=? WHERE host=? AND port=?}, {}, $args->{status}, $args->{host}, $args->{port}) == 1 or Carp::croak("cannot update storage information: " . $self->dbh->errstr);
}

sub ping {
    my $self = shift;
    my $args = args({host => 1, port => 1}, @_);

    try {
        my ($minor_version, $code, $msg, $headers, $body) = $self->ua->request(
            method => 'GET',
            path   => "/?alive",
            host   => $args->{host},
            port   => $args->{port},
        );
        $code =~ /^(?:200|404)$/ ? 1 : 0
    } catch {
        0
    };
}

sub update_storage_status {
    my $self = shift;
    my $args = args({host => 1, port => 1, current_status => 1}, @_);

    if ($self->ping(host => $args->{host}, port => $args->{port})) {
        # alive
        if ($args->{current_status} == STORAGE_STATUS_DEAD) {
            $self->edit_storage_status(host => $args->{host}, port => $args->{port}, status => STORAGE_STATUS_ALIVE);
        }
    } else {
        if ($args->{current_status} == STORAGE_STATUS_ALIVE) {
            $self->edit_storage_status(host => $args->{host}, port => $args->{port}, status => STORAGE_STATUS_DEAD);
        }
    }
}

sub add_bucket {
    my ($self, $name) = @_;

    $self->dbh->do(q{INSERT INTO bucket (name) VALUES (?)},{}, $name) or Carp::croak "Cannot insert bucket: $name: " . $self->dbh->errstr;
}

sub add_storage {
    my $self = shift;
    my $args = args({host => 1, port => 1}, @_);

    my $status = $self->ping(host => $args->{host}, port => $args->{port}) ? STORAGE_STATUS_ALIVE : STORAGE_STATUS_DEAD;
    $self->dbh->do(q{INSERT INTO storage (host, port, status) VALUES (?, ?, ?)},
                        {}, $args->{host}, $args->{port}, $status) or Carp::croak "Cannot insert storage: $args->{host}, $args->{port}: " . $self->dbh->errstr;
}

sub list_storage {
    my $self = shift;

    my $rows = $self->dbh->selectall_arrayref(q{SELECT * FROM storage}, {Slice => {}}) or Carp::croak "Cannot select storage: " . $self->dbh->errstr;
    return wantarray ? @$rows : $rows;
}

sub delete_storage {
    my $self = shift;
    my $args = args({host => 1, port => 1}, @_);

    $self->dbh->do(q{DELETE FROM storage WHERE host=? AND port=?},
                        {}, $args->{host}, $args->{port}) or Carp::croak "Cannot delete storage: $args->{host}, $args->{port}: " . $self->dbh->errstr;
}

1;

