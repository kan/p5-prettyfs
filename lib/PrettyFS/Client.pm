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
use Smart::Args;
use Try::Tiny;
use Data::UUID;
use File::Temp ();
use JSON;
use Storable;

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
    args my $self,
         my $fh,
         my $bucket => {optional => 1},
         my $ext    => {optional => 1},
         ;

    my $size = -s $fh;
    Carp::croak("cannot get file size from fh. It cased by not a real file") unless defined $size;

    # WTF
    (my $uuid = $self->uuid_generator->create_b64()) =~ s/=//g;

    my $path;
    my $bucket_id='';
    if ($bucket) {
        ($bucket_id) = $self->dbh->selectrow_array(q{SELECT id FROM bucket WHERE name=?}, {}, $bucket);
        unless (defined $bucket_id) {
            Carp::croak "unknown bucket: $bucket";
        }
        $path = "/$bucket/$uuid";
    } else {
        $path = "/$uuid";
    }
    $path .= ".$ext" if defined $ext;

    my @storage_nodes = shuffle @{$self->db->search(q{SELECT * FROM storage WHERE status=?}, STORAGE_STATUS_ALIVE)};
    for my $storage (@storage_nodes) {
        my ( $minor_version, $code, $msg, $headers, $body ) =
          $self->ua->request(
            method     => 'PUT',
            path_query => $path,
            host       => $storage->{host},
            port       => $storage->{port},
            content    => $fh,
          );

        if ($code == 200) {
            $self->put_file_post_process($storage->{id}, $bucket_id, $uuid, $size, $ext);
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

    $self->dbh->do(q{INSERT INTO file (uuid, bucket_id, size, ext) VALUES (?, ?, ?, ?)}, {}, $uuid, $bucket_id, $size, $ext) or Carp::croak("cannot insert: " . $self->dbh->errstr);
    $self->dbh->do(q{INSERT INTO file_on (file_uuid, storage_id) VALUES (?,?)}, {}, $uuid, $storage_id) or Carp::croak("cannot insert: " . $self->dbh->errstr);
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

    # start transaction
    $self->dbh->begin_work();

    {
        my ($ext, $bucket_id) = $self->dbh->selectrow_array('SELECT ext, bucket_id FROM file WHERE uuid=?',{Slice => {}}, $uuid);

        # enqueue first.
        $self->jonk->enqueue(
            'PrettyFS::Worker::Deleter',
            Storable::nfreeze([$uuid, $ext, $bucket_id])
        );

        # delete row in file table.
        $self->dbh->do(q{DELETE FROM file WHERE uuid=?}, {}, $uuid) == 1 or die "Cannot delete file table: " . $self->dbh->errstr;
    }

    $self->dbh->commit();
}

sub get_urls {
    my ($self, $uuid) = @_;
    Carp::croak("Missing mandatory parameter: uuid") unless @_ ==2;

    my ($bucket_name, $ext) = $self->dbh->selectrow_array(q{SELECT bucket.name, ext FROM file LEFT JOIN bucket ON (bucket.id=file.bucket_id) WHERE uuid=?}, {}, $uuid) or return;

    my @ret;
    my $sth = $self->dbh->prepare(q{SELECT storage.host, storage.port FROM file INNER JOIN file_on ON (file_on.file_uuid=file.uuid) INNER JOIN storage ON (file_on.storage_id=storage.id) WHERE file.uuid=?}) or Cap::croak($self->dbh->errstr);
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
    args my $self,
         my $host,
         my $port,
         my $status,
         ;

    $self->db->do(q{UPDATE storage SET status=? WHERE host=? AND port=?}, $status, $host, $port);
    if ($status == STORAGE_STATUS_DEAD) {
        $self->jonk->enqueue(
            'PrettyFS::Worker::Reaper',
            "$host:$port"
        ) or Carp::croak($self->jonk->errstr);
    }
}

sub ping {
    args my $self,
         my $host,
         my $port;

    try {
        my ( $minor_version, $code, $msg, $headers, $body ) =
          $self->ua->request(
            method     => 'HEAD',
            path_query => "/__prettyfs_disk_usage__",
            host       => $host,
            port       => $port,
          );
        $code =~ /^(?:200|404)$/ ? 1 : 0 # TODO: only allow 200
    } catch {
        0
    };
}

sub update_storage_status {
    args my $self,
         my $host,
         my $port,
         my $current_status,
         ;

    my $mark_fail = sub {
        if ($current_status == STORAGE_STATUS_ALIVE) {
            $self->edit_storage_status(host => $host, port => $port, status => STORAGE_STATUS_DOWN);
        }
    };

    try {
        my ( $minor_version, $code, $msg, $headers, $body ) =
          $self->ua->request(
            method     => 'GET',
            path_query => "/__prettyfs_disk_usage__",
            host       => $host,
            port       => $port,
          );
        if ($code == 200) {
            # alive
            if ($current_status == STORAGE_STATUS_DOWN) {
                $self->edit_storage_status(host => $host, port => $port, status => STORAGE_STATUS_ALIVE);
            }
            my $data = JSON::decode_json($body);
            # {"available":83846708,"device":"/dev/disk0s2","disk":"/var/folders/MM/MMSDg4lnHS0+J2Aea10zjU+++TI/-Tmp-/Br3pWinSkc","time":1292771992,"total":118153176,"use":"29%","used":34050468}
            $self->dbh->do(q{UPDATE storage SET disk_total=?, disk_used=? WHERE host=? AND port=?}, {}, $data->{total}, $data->{used}, $host, $port) or Carp::croak("cannot update storage information: " . $self->dbh->errstr);
        } else {
            $mark_fail->();
        }
    } catch {
        $mark_fail->();
    };
}

sub add_bucket {
    my ($self, $name) = @_;

    $self->db->do(q{INSERT INTO bucket (name) VALUES (?)}, $name);
}

sub add_storage {
    args my $self,
         my $host,
         my $port,
         ;

    my $status = $self->ping(host => $host, port => $port) ? STORAGE_STATUS_ALIVE : STORAGE_STATUS_DOWN;
    $self->db->do(q{INSERT INTO storage (host, port, status) VALUES (?, ?, ?)}, $host, $port, $status);
}

sub list_storage {
    my $self = shift;

    my @rows = $self->db->search(q{SELECT * FROM storage});
    return wantarray ? @rows : \@rows;
}

sub delete_storage {
    args my $self,
         my $host,
         my $port,
         ;

    $self->db->do(q{DELETE FROM storage WHERE host=? AND port=?}, $host, $port);
}

1;

