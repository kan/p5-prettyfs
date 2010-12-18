package PrettyFS::Client;
use strict;
use warnings FATAL => 'all';
use utf8;
use Class::Accessor::Lite (
    new => 0,
    ro  => [qw/dbh db ua jonk uuid_generator/],
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
use File::Temp ();

sub new {
    my $class = shift;

    my %args = @_==1 ? %{$_[0]} : @_;
    Carp::croak("missing mandatory parameter: dbh") unless exists $args{dbh};

    my $self = bless {%args}, $class;
    $self->{ua}   ||= Furl::HTTP->new();
    $self->{jonk} ||= Jonk::Client->new($self->dbh);
    $self->{db}     = PrettyFS::DB->new({dbh => $self->dbh});
    $self->{uuid_generator} ||= Data::UUID->new();
    return $self;
}

sub put_file {
    my $self = shift;
    my $args = args({fh => 1, bucket => 0, ext => 0, size => 0}, @_);
    my $size = defined($args->{size}) ? $args->{size} : -s $args->{fh};

    # WTF
    (my $uuid = $self->uuid_generator->create_b64()) =~ s/=//g;

    my $path;
    my $bucket_id='';
    if ($args->{bucket}) {
        ($bucket_id) = $self->dbh->selectrow_array(q{SELECT id FROM bucket WHERE name=?}, {}, $args->{bucket});
        unless (defined $bucket_id) {
            Carp::croak "unknown bucket: $args->{bucket}";
        }
        $path = "/$args->{bucket}/$uuid";
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
            $self->edit_storage_status(host => $storage->{host}, port => $storage->{port}, status => STORAGE_STATUS_DOWN);
        } else {
            ; # nop.
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

sub get_file_fh {
    my ($self, $uuid) = @_;
    Carp::croak("Missing mandatory parameter: uuid") unless @_ ==2;

    my @urls = $self->get_urls($uuid);
    for my $url (@urls) {
        my $temp = File::Temp->new();
        my $res = try {
            my ($minor_version, $code, $msg, $headers, $body) = $self->ua->request(
                method     => 'GET',
                url        => $url,
                write_file => $temp,
            );
            return 1 if $code == 200;
            return 0;
        };
        return ($temp, $url) if $res;
    }
    return undef;
}

sub delete_file {
    my ($self, $uuid) = @_;
    Carp::croak("Missing mandatory parameter: uuid") unless @_ ==2;

    $self->db->do(q{UPDATE file SET del_fg=1 WHERE uuid=?}, $uuid);
    $self->jonk->enqueue(
        'PrettyFS::Worker::Deleter',
        $uuid
    );
}

sub get_urls {
    my ($self, $uuid) = @_;
    Carp::croak("Missing mandatory parameter: uuid") unless @_ ==2;

    my ($bucket_name, $ext) = $self->dbh->selectrow_array(q{SELECT bucket.name, ext FROM file LEFT JOIN bucket ON (bucket.id=file.bucket_id) WHERE uuid=?}, {}, $uuid) or return;

    my @ret;
    my $sth = $self->dbh->prepare(q{SELECT storage.host, storage.port FROM file INNER JOIN storage ON (file.storage_id=storage.id) WHERE file.uuid=? AND del_fg!=1}) or Cap::croak($self->dbh->errstr);
    $sth->execute($uuid) or Cap::croak($self->dbh->errstr);
    while (my ($host, $port) = $sth->fetchrow_array()) {
        my $url  = "http://${host}:${port}";
           $url .= "/$bucket_name" if defined $bucket_name;
           $url .= "/$uuid";
           $url .= ".$ext"         if defined $ext;

        push @ret, $url;
    }
    return wantarray ? @ret : \@ret;
}

sub edit_storage_status {
    my $self = shift;
    my $args = args({host => 1, port => 1, status => 1}, @_);

    $self->db->do(q{UPDATE storage SET status=? WHERE host=? AND port=?}, $args->{status}, $args->{host}, $args->{port});
    if ($args->{status} == STORAGE_STATUS_DEAD) {
        $self->jonk->enqueue(
            'PrettyFS::Worker::Reaper',
            "$args->{host}:$args->{port}"
        ) or Carp::croak($self->jonk->errstr);
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
        if ($args->{current_status} == STORAGE_STATUS_DOWN) {
            $self->edit_storage_status(host => $args->{host}, port => $args->{port}, status => STORAGE_STATUS_ALIVE);
        }
    } else {
        if ($args->{current_status} == STORAGE_STATUS_ALIVE) {
            $self->edit_storage_status(host => $args->{host}, port => $args->{port}, status => STORAGE_STATUS_DOWN);
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

    my $status = $self->ping(host => $args->{host}, port => $args->{port}) ? STORAGE_STATUS_ALIVE : STORAGE_STATUS_DOWN;
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

