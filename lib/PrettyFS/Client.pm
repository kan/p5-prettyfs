package PrettyFS::Client;
use strict;
use warnings FATAL => 'all';
use utf8;
use Class::Accessor::Lite (
    new => 0,
    ro  => [qw/dbh db ua jonk/],
);
use Carp ();
use PrettyFS::Constants;
use PrettyFS::DB;
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
    $self->{ua}   ||= Furl::HTTP->new();
    $self->{jonk} ||= Jonk::Client->new($self->dbh);
    $self->{db}     = PrettyFS::DB->new({dbh => $self->dbh});
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
        my $bucket = $self->db->single(q{SELECT * FROM bucket WHERE name=?}, $args->{bucket});
        unless ($bucket) {
            Carp::croak "unknown bucket: $args->{bucket}";
        }
        $bucket_id = $bucket->{id};
        $path = "/$bucket->{name}/$uuid";
    } else {
        $path = "/$uuid";
    }
    $path .= ".$args->{ext}" if $args->{ext};

    my @storage_nodes = shuffle @{$self->db->search(q{SELECT * FROM storage WHERE status=?}, STORAGE_STATUS_ALIVE)};
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

    $self->db->do(q{INSERT INTO file (uuid, storage_id, bucket_id, size, ext) VALUES (?, ?, ?, ?, ?)}, $uuid, $storage_id, $bucket_id, $size, $ext);
    $self->jonk->enqueue(
        'PrettyFS::Worker::Replication',
        $uuid
    );
}

sub delete_file {
    my ($self, $uuid) = @_;

    $self->db->do(q{UPDATE file SET del_fg=1 WHERE uuid=?}, $uuid);
    $self->jonk->enqueue(
        'PrettyFS::Worker::Deleter',
        $uuid
    );
}

sub get_urls {
    my ($self, $uuid) = @_;

    my $file = $self->db->single(q{SELECT * FROM file WHERE uuid=?}, $uuid) or return;

    my $bucket;
    if ($file->{bucket_id}) {
        $bucket = $self->db->single(q{SELECT * FROM bucket WHERE id=?}, $file->{bucket_id});
        unless ($bucket) {
            Carp::croak "unknown bucket: $bucket";
        }
    }

    my @ret;
    my @files = $self->db->search(q{SELECT storage.* FROM file INNER JOIN storage ON (file.storage_id=storage.id) WHERE file.uuid=?}, $uuid);
    for my $row (@files) {
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

    $self->db->do(q{UPDATE storage SET status=? WHERE host=? AND port=?}, $args->{status}, $args->{host}, $args->{port});
    if ($args->{status} == STORAGE_STATUS_DEAD) {
        $self->jonk->enqueue(
            'PrettyFS::Worker::Repair',
            "$args->{host}:$args->{port}"
        );
    }
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

    $self->db->do(q{INSERT INTO bucket (name) VALUES (?)}, $name);
}

sub add_storage {
    my $self = shift;
    my $args = args({host => 1, port => 1}, @_);

    my $status = $self->ping(host => $args->{host}, port => $args->{port}) ? STORAGE_STATUS_ALIVE : STORAGE_STATUS_DEAD;
    $self->db->do(q{INSERT INTO storage (host, port, status) VALUES (?, ?, ?)}, $args->{host}, $args->{port}, $status);
}

sub list_storage {
    my $self = shift;

    my @rows = $self->db->search(q{SELECT * FROM storage});
    return wantarray ? @rows : \@rows;
}

sub delete_storage {
    my $self = shift;
    my $args = args({host => 1, port => 1}, @_);

    $self->db->do(q{DELETE FROM storage WHERE host=? AND port=?}, $args->{host}, $args->{port});
}

1;

